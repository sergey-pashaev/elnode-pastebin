;;; elnode-pastebin.el

(require 'elnode)
(require 'emacs-template)
(require 'htmlize)

;; constants
(defconst elnode-pastebin-port 8001
  "Default application port.")

(defconst elnode-pastebin-urls
  '(("^/$" . elnode-pastebin-index-handler)
    ("^/new/$" . elnode-pastebin-get-id-handler)
    ("^/get/\\([a-fA-F0-9]+\\)" . elnode-pastebin-get-handler)
    ("^/raw/\\([a-fA-F0-9]+\\)" . elnode-pastebin-get-raw-handler))
  "Regexp to handler map.")

(defconst elnode-pastebin-languages-file-extensions
  '(("txt" . "fundamental-mode")
    ("el" . "emacs-lisp-mode")
    ("c" . "c-mode")
    ("cpp" . "c++-mode")
    ("java" . "java-mode")
    ("xml" . "xml-mode")
    ("html" . "html-mode")
    ("js" . "javascript-mode"))
  "File extension to mode map.")

(defconst elnode-pastebin-languages-names
  '(("txt" . "")
    ("el" . "Emacs Lisp")
    ("c" . "C")
    ("cpp" . "C++")
    ("java" . "Java")
    ("xml" . "XML")
    ("html" . "HTML")
    ("js" . "Javascript"))
  "File extension to language name map.")

;; global variables
(defvar elnode-pastebin-is-running nil)
(defvar elnode-pastebin-hash-table nil)

;; paths and filenames
(defvar elnode-pastebin-dir (expand-file-name "~/.emacs.d/utils/pastebin/"))
(defvar elnode-pastebin-public-dir (concat elnode-pastebin-dir "public_html/"))
(defvar elnode-pastebin-files-dir (concat elnode-pastebin-dir "files/"))
(defvar elnode-pastebin-templates-dir (concat elnode-pastebin-dir "templates/"))
(defvar elnode-pastebin-hash-table-filename (concat elnode-pastebin-dir "pastebin-hash.el"))

;; structs
(defstruct elnode-paste id lang author cdate edate)

;; load/save hash table
(defun elnode-pastebin-load-hash-table ()
  (with-temp-buffer
    (insert-file-contents elnode-pastebin-hash-table-filename)
    (let ((value (read (buffer-string))))
      (if (hash-table-p value)
          (setq elnode-pastebin-hash-table value)
        (setq elnode-pastebin-hash-table (make-hash-table :test 'equal))))))

(defun elnode-pastebin-save-hash-table ()
  (with-temp-file elnode-pastebin-hash-table-filename
    (insert (prin1-to-string elnode-pastebin-hash-table))))

;; base handlers
(defun elnode-pastebin-dispatcher-handler (httpcon)
  "Main url dispather"
  (elnode-dispatcher httpcon elnode-pastebin-urls 'elnode-pastebin-404-handler))

(defun elnode-pastebin-404-handler (httpcon)
  "404 eror handler."
  (elnode-http-start httpcon 404 '("Content-Type" . "text/html"))
  (elnode-send-file httpcon (concat elnode-pastebin-public-dir "404.html")))

(defun elnode-pastebin-index-handler (httpcon)
  "Index page handler."
  (elnode-http-start httpcon 200 '("Content-Type" . "text/html"))
  (elnode-send-file httpcon (concat elnode-pastebin-public-dir "index.html")))

(defun elnode-pastebin-make-paste (httpcon)
  (let ((cdate (current-time)))
    (make-elnode-paste :id (md5 (prin1-to-string cdate))
                       :lang (if (assoc (elnode-http-param httpcon "lang")
                                        elnode-pastebin-languages-file-extensions)
                                 (elnode-http-param httpcon "lang")
                               "txt")
                       :author (if (string= (elnode-http-param httpcon "author") "")
                                   "anonymous"
                                 (elnode-http-param httpcon "author"))
                       :cdate cdate
                       :edate (time-add cdate
                                        (seconds-to-time (string-to-number (elnode-http-param httpcon "expires")))))))

(defun elnode-pastebin-get-paste-filename (paste)
  (concat elnode-pastebin-files-dir
          (elnode-paste-id paste)
          "."
          (elnode-paste-lang paste)))

(defun elnode-pastebin-save-paste (httpcon)
  (let* ((paste (elnode-pastebin-make-paste httpcon))
         (text (elnode-http-param httpcon "text")))
    (when (not (string= text ""))
      (puthash (elnode-paste-id paste) paste elnode-pastebin-hash-table)
      (with-temp-file (elnode-pastebin-get-paste-filename paste)
        (setq coding-system-for-write 'utf-8)
        (insert text)))
    paste))

(defun elnode-pastebin-common-create-handler (httpcon status mime func)
  (elnode-http-start httpcon status '("Content-Type" . mime))
  (let ((paste (elnode-pastebin-save-paste httpcon)))
    (elnode-http-return httpcon (funcall func paste))))

(defun elnode-pastebin-get-id-handler (httpcon)
  (elnode-pastebin-common-create-handler
   httpcon 200 "text/plain"
   (lambda (paste)
     (elnode-paste-id paste))))

(defun elnode-pastebin-get-handler (httpcon)
  (elnode-http-start httpcon 200 '("Content-Type" . "text/html"))
  (let* ((paste (gethash (elnode-http-mapping httpcon 1) elnode-pastebin-hash-table))
         (filename (elnode-pastebin-get-paste-filename paste))
         (langname (cdr (assoc (elnode-paste-lang paste) elnode-pastebin-languages-names)))
         (mode (cdr (assoc (elnode-paste-lang paste) elnode-pastebin-languages-file-extensions))))
    (elnode-http-return httpcon
      (render-template
       (with-current-buffer (find-file-noselect (concat elnode-pastebin-templates-dir "get.mustache"))
         (buffer-string))
       (hash-map "author" (elnode-paste-author paste)
                 "langname" langname
                 "id" (elnode-paste-id paste)
                 "cdate" (format-time-string "%d.%m.%Y %H:%M" (elnode-paste-cdate paste))
                 "edate" (format-time-string "%d.%m.%Y %H:%M" (elnode-paste-edate paste))
                 ;"style" "color: #dcdccc;background-color: #3f3f3f;"
                 "text" (elnode-pastebin-htmlize-file-to-string filename mode))))))

(defun elnode-pastebin-get-raw-handler (httpcon)
  (elnode-http-start httpcon 200 '("Content-Type" . "text/plain"))
  (let* ((paste (gethash (elnode-http-mapping httpcon 1) elnode-pastebin-hash-table))
         (filename (elnode-pastebin-get-paste-filename paste)))
    (elnode-send-file httpcon filename)))

;; htmlize utils
(defun elnode-pastebin-htmlize-file-to-string (filename mode)
  (let (result)
    (with-temp-buffer
      (insert-file-contents filename)
      (funcall (intern mode))
      (font-lock-fontify-buffer)
      (setq result (htmlize-region-for-paste (point-min) (point-max))))
    result))

;; public service functions
(defun elnode-pastebin-start ()
  (interactive)
  (elnode-pastebin-load-hash-table)
  (when
      (elnode-start 'elnode-pastebin-dispatcher-handler
                    :port elnode-pastebin-port
                    :host "localhost")
    (setq elnode-pastebin-is-running t)))

(defun elnode-pastebin-stop ()
  (interactive)
  (elnode-pastebin-save-hash-table)
  (elnode-stop elnode-pastebin-port)
  (setq elnode-pastebin-is-running nil))

(defun elnode-pastebin-restart ()
  (interactive)
  (when elnode-pastebin-is-running
    (elnode-pastebin-stop))
  (elnode-pastebin-start))

(defun elnode-pastebin-buffer ()
  "Make paste from buffer."
  (interactive)
  (message "Not implemented yet."))

(defun elnode-pastebin-region ()
  "Make paste from region."
  (interactive)
  (message "Not implemented yet."))

(provide 'elnode-pastebin)

;;; elnode-itls.el ends here

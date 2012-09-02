# elnode-pastebin
Simple pastebin application based on elnode.

# dependencies
* [elnode](https://github.com/nicferrier/elnode)
* [emacs-template](https://github.com/dbushenko/emacs-template)
* htmlize (Emacs 24: `M-x package-install htmlize`)

# install
1. install all dependencies
2. git clone git://github.com/sergey-pashaev/elnode-pastebin.git
3. set variable `elnode-pastebin-dir` to cloned repo directory.
4. `(add-to-list 'load-path "/<path to elnode-pastebin dir here>/")`
5. add `(require 'elnode-pastebin)` to your configuration file.
6. `M-x elnode-pastebin-start RET`

# features
* simple syntax highlighting via htmlize

# todo
* paste (current) buffer
* paste region
* using elnode-db instead simple hash-table (not such a big difference at this moment =))
* remove expired pastes

;;; tramp-auto-auth.el --- TRAMP automatic authentication library -*- lexical-binding: t -*-

;; Copyright (C) 2019 Bruno Félix Rezende Ribeiro <oitofelix@gnu.org>

;; Author: Bruno Félix Rezende Ribeiro <oitofelix@gnu.org>
;; Keywords: comm, processes
;; Package: tramp-auto-auth
;; Homepage: https://github.com/oitofelix/tramp-auto-auth
;; Version: 20190928.1932
;; Package-Requires: ((emacs "24.4") (tramp "0.0"))

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This library provides ‘tramp-auto-auth-mode’: a global minor mode
;; whose purpose is to automatically feed TRAMP sub-processes with
;; passwords for paths matching regexps.  This is useful in situations
;; where interactive user input is not desirable or feasible.  For
;; instance, in sub-nets with large number of hosts or whose hosts
;; have dynamic IPs assigned to them.  In those cases it’s not
;; practical to query passwords using the ‘auth-source’ library
;; directly, since this would require each host to be listed
;; explicitly and immutably in a Netrc file.  Another scenario where
;; this mode is useful are non-interactive Emacs sessions (like those
;; used for batch processing or by evaluating ‘:async’ Org Babel
;; source blocks) in which it’s impossible for the user to answer a
;; password-asking prompt.
;;
;; When a TRAMP prompt is encountered, ‘tramp-auto-auth-mode’ queries
;; the alist ‘tramp-auto-auth-alist’ for the auth-source spec value
;; whose regexp key matches the correspondent TRAMP path.  This spec
;; is then used to query the auth-source library for a presumably
;; phony entry exclusively dedicated to the whole class of TRAMP
;; paths matching that regexp.
;;
;; To make use of the automatic authentication feature, on the Lisp
;; side the variable ‘tramp-auto-auth-alist’ must be customized to
;; hold the path regexps and their respective auth-source specs, and
;; then ‘tramp-auto-auth-mode’ must be enabled.  For example:
;;
;; ---- ~/.emacs.el -------------------------------------------------
;; (require 'tramp-auto-auth)
;;
;; (add-to-list
;;  'tramp-auto-auth-alist
;;  '("root@10\\.0\\." .
;;    (:host "Funny-Machines" :user "root" :port "ssh")))
;;
;; (tramp-auto-auth-mode)
;; ------------------------------------------------------------------
;;
;; After this, just put the respective sacred secret in an
;; authentication source supported by auth-source library.  For
;; instance:
;;
;; ---- ~/.authinfo.gpg ---------------------------------------------
;; machine Funny-Machines login root password "$r00tP#sWD!" port ssh
;; ------------------------------------------------------------------
;;
;; In case you are feeling lazy or the secret is not so secret (nor so
;; sacred) -- or for any reason you need to do it all from Lisp --
;; it’s enough to:
;;
;; (auth-source-remember '(:host "Funny-Machines" :user "root" :port "ssh")
;; 		         '((:secret "$r00tP#sWD!")))
;;
;; And happy TRAMPing!

;;; Code:


(require 'tramp)
(require 'auth-source)


(defcustom tramp-auto-auth-alist
  nil
  "Alist of TRAMP paths regexps and their respective auth-source SPEC.
Each element has the form (PATH-REGEXP . SPEC), where PATH-REGEXP
is a regular expression to be matched against TRAMP paths and
SPEC is the respective auth-source SPEC which will be used to
retrieve the password to be sent to the TRAMP’s sub-process in
case a match does occur.

SPEC is exactly the one expected by ‘auth-source-search’."
  :type '(alist
	  :key-type
	  (string :tag "Path Regexp"
		  :help-echo "Regexp which matches the desired TRAMP path")
	  :value-type
	  (plist :key-type (choice :tag "Key"
				   :help-echo "Auth-source spec key"
				   (const :tag "Host" :host)
				   (const :tag "User" :user)
				   (const :tag "Port" :port)
				   (symbol :tag "Other keyword"))
		 :value-type (string :tag "Value"
				     :help-echo "Auth-source spec value")
		 :tag "Auth-source spec"
		 :help-echo "Password for the TRAMP path resource"))
  :group 'tramp
  :require 'tramp-auto-auth)

;;;###autoload
(define-minor-mode tramp-auto-auth-mode
  "Toggle Tramp-Auto-Auth global minor mode on or off.
With a prefix argument ARG, enable Tramp-Auto-Auth mode if ARG is
positive, and disable it otherwise.  If called from Lisp, enable
the mode if ARG is omitted or nil, and toggle it if ARG is ‘toggle’.

When enabled ‘tramp-auto-auth-alist’ is used to automatically
authenticate to remote servers."
  :group 'tramp
  :global t
  :require 'tramp-auto-auth
  (if tramp-auto-auth-mode
      (progn
	(advice-add #'tramp-action-password :around
		    (lambda (tramp-action-password proc vec)
		      (pcase (or (car (last vec)) "")
			((and (app (lambda (expval)
				     (assoc-default expval
						    tramp-auto-auth-alist
						    #'string-match-p))
				   spec)
			      (guard spec)
			      (let pre-secret (plist-get
					       (car (apply
						     #'auth-source-search
						     spec))
					       :secret))
			      (guard pre-secret)
			      (let secret (if (functionp pre-secret)
					      (funcall pre-secret)
					    pre-secret))
			      (guard secret))
			 (process-send-string
			  proc (concat secret tramp-local-end-of-line)))
			(_ (funcall tramp-action-password proc vec))))
		    '((name . tramp-auto-auth-mode)))
	(advice-add #'tramp-action-yesno :around
		    (lambda (tramp-action-yesno proc vec)
		      (pcase (or (car (last vec)) "")
			((pred (lambda (expval)
				 (assoc-default expval tramp-auto-auth-alist
						#'string-match-p)))
			 (tramp-send-string
			  vec (concat "yes" tramp-local-end-of-line)))
			(_ (funcall tramp-action-yesno proc vec))))
		    '((name . tramp-auto-auth-mode))))
    (advice-remove #'tramp-action-password 'tramp-auto-auth-mode)
    (advice-remove #'tramp-action-yesno 'tramp-auto-auth-mode)))


(provide 'tramp-auto-auth)

;;; tramp-auto-auth.el ends here

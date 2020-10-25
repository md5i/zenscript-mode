;;; zenscript-language.el --- Tools for understanding ZenScript code. -*- lexical-binding: t -*-

;; Copyright (c) 2020 Eutro

;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to deal
;; in the Software without restriction, including without limitation the rights
;; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;; copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:

;; The above copyright notice and this permission notice shall be included in all
;; copies or substantial portions of the Software.

;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.

;;; Commentary:

;; ZenScript language module, for understanding ZenScript code.

;;; Code:

(require 'zenscript-common)
(require 'zenscript-parser)

(defun zenscript--java-type-to-ztype (symbol)
  "Convert a Java type to a ZenType.

SYMBOL should be a java class name to be looked up in dumpzs."
  (car
   (seq-find (lambda (entry)
	       (equal (cadr entry) symbol))
	     (cdr (assoc "Types" (cdr (zenscript-get-dumpzs)))))))

(defun zenscript--symbol-to-type (symbol)
  "Get the ZenType from a stringified binding object SYMBOL.

If SYMBOL is the string:

 \"SymbolJavaStaticField: public static zenscript.Type ZenScriptGlobals.global\"

Then its ZenType will be resolved by looking up the zsPath of \"zenscript.Type\"."
  (when (string-match "SymbolJavaStatic\\(?:Field\\|\\(Method: JavaMethod\\)\\): public static \\(.+\\) .+$" symbol)
    (concat (if (match-string 1) "=>" "") (zenscript--java-type-to-ztype (match-string 2 symbol)))))

(defun zenscript--buffer-vals ()
  "Get a list of resolvable values in a buffer.

Returns a list of values of the form:

 (name type)

name:

  The name of the value by which it can be referenced.

type:

  The ZenType of the value, its `zsPath` from dumpzs, or nil if unknown."
  (append
   (mapcar (lambda (el)
	     (list (car el)
		   (zenscript--symbol-to-type (cadr el))))
	   (cdr (assoc "Globals" (cdr (zenscript-get-dumpzs)))))
   (mapcar (lambda (import)
	     (or (caddr import)
		 (last (car import))))
	   (cadr zenscript--parse-buffer-cache))))

(defun zenscript--get-importables-1 (nodes)
  "Get a list of types or static members below NODES in the tree."
  (apply 'append
	 (mapcar (lambda (node)
		   (if (stringp node)
		       (list node)
		     (let ((name (car node)))
		       ;; This operates on the assumption that type names start
		       ;; with capital letters.
		       (if (string= "Lu" (get-char-code-property (string-to-char name)
								 'general-category))
			   (cons name
				 (mapcar (lambda (member)           ; "[STATIC] "
					   (concat name "." (substring member 9)))
					 (seq-filter (lambda (member)
						       (string-match-p "\\[STATIC\\] .+" member))
						     (mapcar (lambda (node)
							       (if (stringp node)
								   node
								 (car node)))
							     (cdr node)))))
			 (mapcar (lambda (importable)
				   (concat name "." importable))
				 (zenscript--get-importables-1 (cdr node)))))))
		 nodes)))

(defun zenscript--get-members (&optional types)
  "Get the known members of the ZenTypes TYPES, or just all known members.

Returns a list of members of the following format:

 (name . extra-info)

name:

  The name of the member.

extra-info:

  A list (possibly nil) of extra information relating to the member."
  (if types
      ()
    (apply 'append
	   (mapcar (lambda (type)
		     (cdr (assoc 'members type)))
		   (cdr (assoc 'zenTypeDumps (car (zenscript-get-dumpzs))))))))

(defun zenscript--get-importables ()
  "Get a list of all things that can be imported: static members and types.

Returns a list of type names that can be imported."
  (zenscript--get-importables-1 (cdr (assoc "Root (Symbol Package)" (cdr (zenscript-get-dumpzs))))))

(defvar zenscript--parse-buffer-cache ()
  "This is the cache maintained by `zenscript-parse-buffer`.")

(defcustom zenscript-buffer-parse-timer-function 'zenscript-default-buffer-parse-timer-function
  "The function by which it is determined how often the buffer should be parsed.

Must take a buffer and return a number of seconds in which the buffer
should be parsed next.

See `zenscript-parse-buffer`.")

(defun zenscript-default-buffer-parse-timer-function (buffer)
  "The default value of `zenscript-parse-buffer-timer-function`.

Constantly returns 5.

BUFFER is ignored."
  5)

(defun zenscript-parse-buffer (buffer)
  "Parse the buffer BUFFER, refreshing the cache.

This is run periodically while in `zenscript-mode`."
  (when (eq (with-current-buffer buffer
	      major-mode)
	    'zenscript-mode)
    (run-at-time (funcall zenscript-buffer-parse-timer-function
			  buffer)
		 ()
		 (lambda ()
		   (zenscript-parse-buffer buffer)))
    (let ((hash (buffer-hash buffer)))
      (when (not (string= hash (car zenscript--parse-buffer-cache)))
	(setq zenscript--parse-buffer-cache
	      (cons hash
		    (zenscript--parse-tokens
		     (with-current-buffer buffer
		       (save-excursion (zenscript--tokenize-buffer))))))))))

(defun zenscript--init-language ()
  "Initialize the language module."
  (make-local-variable 'zenscript--parse-buffer-cache)
  (zenscript-parse-buffer (current-buffer)))

(provide 'zenscript-language)
;;; zenscript-language.el ends here

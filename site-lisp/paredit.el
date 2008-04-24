;;; -*- Mode: Emacs-Lisp; outline-regexp: "\n;;;;+" -*-

;;;;;; Paredit: Parenthesis-Editing Minor Mode
;;;;;; Version 1.0

;;; This is my revisied version of paredit.el.  All contents are placed in the
;;; public domain.  Major parts of this code were originally written by Taylor
;;; R. Campbell (except where explicitly noted) and placed in the Public
;;; Domain.  All warranties are disclaimed.

;;; The following changes have been made to the original paredit.el mode by
;;; Taylor R. Campbell:
;;;
;;; - M-r is changed to M-g, since I use M-r constantly to reposition my
;;;   cursor, but I never used M-g in Lisp mode.  Think of 'g' as in "grab".
;;;
;;; - C-c C-M-l is now C-c C-l.
;;;
;;; - TAB completes the current symbol, after reindenting the line.
;;;
;;; - ) inserts a closing parenthesis if there is no top-level balancing
;;;   parenthesis.  Example:
;;;     (defun foo()|           ; if you enter ) here, ) gets inserted
;;;
;;; - If you press backspace and the closing parenthesis before point has no
;;;   matching parenthesis, it is deleted (in paredit, the cursor would just
;;;   move past it).  This and the previous change are meant to facilitate
;;;   cutting and pasting where properly matched parentheses might end up
;;;   missing.
;;;
;;; - The behaviors of ) and M-) are reversed by default.  This means M-)
;;;   reformats your code, but ) won't.
;;;
;;; - There are new sexp manipulation functions.  It may take using them to
;;;   get the hang of it, but the reason they were created is that I needed
;;;   them so often and found myself doing a tons of other keystrokes just to
;;;   emulate them.
;;;
;;;   Before: C-(    backward slurp    foo (|bar) => (foo |bar)
;;;           C-)    forward slurp     (|foo) bar => (|foo bar)
;;;           C-{    backward barf     (foo |bar) => foo (|bar)
;;;           C-}    forward barf      (|foo bar) => (|foo) bar
;;;
;;;   Added:  C-M-(  backward join     (foo) |bar => (foo |bar)
;;;           C-M-)  forward join      |foo (bar) => (|foo bar)
;;;           C-M-{  backward leave    (|foo bar) => |foo (bar)
;;;           C-M-}  forward leave     (foo |bar) => (foo) |bar
;;;
;;;           C-M-,  backward adopt    (foo) (|bar) => (foo |bar)
;;;           C-M-.  forward adopt     (|foo) (bar) => (|foo bar)
;;;           C-M-<  backward orphan   (foo |bar)   => (foo) (|bar)
;;;           C-M->  forward orphan    (|foo bar)   => (|foo) (bar)
;;;
;;;   One example of where backward joining comes in super handy:
;;;
;;;     (let ((foo bar))
;;;       (some code))
;;;     (hello |)         ; point is at the |
;;;
;;;   Say you want is to reference `foo' in the call to `hello', so you need
;;;   the hello form to be within the let form.  Previously, this required
;;;   typing:
;;;
;;;     C-M-u C-M-k C-M-b C-M-n C-b RET C-y
;;;
;;;   There are other key sequences that would be more efficient, surely, but
;;;   that depends on context.  If you think purely in terms of sexps, the
;;;   above sequence always works.
;;;
;;;   You can now accomplish all of this safely in this example by typing:
;;;
;;;      C-M-(
;;;
;;; - New refactoring commands:
;;;
;;;   C-c M-l   refactor the current sexp into an enclosing let variable.
;;;             with prefix arg, pull it out that many levels
;;;
;;;   C-c M-f   refactor the current sexp into an enclosing flet function.
;;;             with prefix arg, pull it out that many levels
;;;
;;;   C-c M-c   convolute the current sexp outward.  User is responsible
;;;             for ensuring that this is a meaningful operation.  It turns:
;;;
;;;               (defun test-function ()
;;;                 (let ((a "hello"))
;;;                   (while a|
;;;                     (hello-world))))
;;;             into:
;;;
;;;               (defun test-function ()
;;;                 |(while a
;;;                   (let ((a "hello"))
;;;                     (hello-world))))
;;;
;;;             By default, the body is extracted after the second inner
;;;             element (after "while a").  Use a prefix argument to extract
;;;             more, such as 3 with `multiple-value-bind'.
;;;
;;; - M-q is bound to `paredit-reindent-defun'.  This calls the ordinary
;;;   `fill-paragraph' if point is in a comment or string, otherwise it
;;;   reindents the current defun.
;;;
;;; - The command `check-parens' is called after every save.  This ensures you
;;;   don't mistakenly save the file and then send it to the Lisp compiler
;;;   expecting things to work.

;;; Add this to your .emacs after adding paredit.el to /path/to/elisp/:
;;;
;;;   (add-to-list 'load-path "/path/to/elisp/")
;;;   (autoload 'paredit-mode "paredit"
;;;     "Minor mode for pseudo-structurally editing Lisp code."
;;;     t)
;;;   (add-hook '...-mode-hook 'turn-on-paredit-mode)
;;;
;;; Usually the ... will be lisp or scheme or both.  Alternatively, you
;;; can manually toggle this mode with M-x paredit-mode.  Customization
;;; of paredit can be accomplished with `eval-after-load':
;;;
;;;   (eval-after-load 'paredit
;;;     '(progn ...redefine keys, &c....))
;;;
;;; This should run in GNU Emacs 21 or later and XEmacs 21.5 or later.  It is
;;; highly unlikely to work in earlier versions of GNU Emacs, and it may have
;;; obscure problems in earlier versions of XEmacs due to the way its syntax
;;; parser reports conditions, as a result of which the code that uses the
;;; syntax parser must mask *all* error conditions, not just those generated
;;; by the syntax parser.

;;; This mode changes the keybindings for a number of simple keys, notably (,
;;; ), ", \, and ;.  The bracket keys (round or square) are defined to insert
;;; parenthesis pairs and move past the close, respectively; the double-quote
;;; key is multiplexed to do both, and also insert an escape if within a
;;; string; backslashes prompt the user for the next character to input,
;;; because a lone backslash can break structure inadvertently; and semicolons
;;; ensure that they do not accidentally comment valid structure.  (Use M-; to
;;; comment an expression.)  These all have their ordinary behaviour when
;;; inside comments, and, outside comments, if truly necessary, you can insert
;;; them literally with C-q.
;;;
;;; Paredit changes the bindings of keys for deleting and killing, so that
;;; they will not destroy any S-expression structure by killing or deleting
;;; only one side of a bracket or quote pair.  If the point is on a closing
;;; bracket, DEL will move left over it; if it is on an opening bracket, C-d
;;; will move right over it.  Only if the point is between a pair of brackets
;;; will C-d or DEL delete them, and in that case it will delete both
;;; simultaneously.  M-d and M-DEL kill words, but skip over any S-expression
;;; structure.  C-k kills from the start of the line, either to the line's
;;; end, if it contains only balanced expressions; to the first closing
;;; bracket, if the point is within a form that ends on the line; or up to the
;;; end of the last expression that starts on the line after the point.
;;;
;;; Automatic reindentation is performed as locally as possible, to ensure
;;; that Emacs does not interfere with custom indentation used elsewhere in
;;; some S-expression.  It is performed only by the advanced S-expression
;;; frobnication commands, and only on the forms that were immediately
;;; operated upon (& their subforms).
;;;
;;; This code is written for clarity, not efficiency.  S-expressions are
;;; frequently walked over redundantly.  If you have problems with some of the
;;; commands taking too long to execute, tell me, but first make sure that
;;; what you're doing is reasonable: it is stylistically bad to have huge,
;;; long, hideously nested code anyway.

(defconst paredit-version "1.0")

(eval-and-compile

  (defun paredit-xemacs-p ()
    ;; No idea I got this definition from.  Edward O'Connor (hober on
    ;; IRC) suggested the current definition.
    ;;   (and (boundp 'running-xemacs)
    ;;        running-xemacs)
    (featurep 'xemacs))

  (defun paredit-gnu-emacs-p ()
    (not (paredit-xemacs-p)))

  (defmacro xcond (&rest clauses)
    "Exhaustive COND.
Signal an error if no clause matches."
    `(cond ,@clauses
	   (t (error "XCOND lost."))))

  (defalias 'paredit-warn (if (fboundp 'warn) 'warn 'message))

  (defvar paredit-sexp-error-type
    (with-temp-buffer
      (insert "(")
      (condition-case condition
	  (backward-sexp)
	(error (if (eq (car condition) 'error)
		   (paredit-warn "%s%s%s%s"
				  "Paredit is unable to discriminate"
				  " S-expression parse errors from"
				  " other errors. "
				  " This may cause obscure problems. "
				  " Please upgrade Emacs."))
	       (car condition)))))

  (defmacro paredit-handle-sexp-errors (body &rest handler)
    `(condition-case ()
	 ,body
       (,paredit-sexp-error-type ,@handler)))

  (put 'paredit-handle-sexp-errors 'lisp-indent-function 1)

  (defmacro paredit-ignore-sexp-errors (&rest body)
    `(paredit-handle-sexp-errors (progn ,@body)
       nil))

  (put 'paredit-ignore-sexp-errors 'lisp-indent-function 0)

  nil)

;;;; Minor Mode Definition

(defvar paredit-mode-map (make-sparse-keymap)
  "Keymap for the paredit minor mode.")

(define-minor-mode paredit-mode
  "Minor mode for pseudo-structurally editing Lisp code.
\\<paredit-mode-map>"
  :lighter " Paredit"
  ;; If we're enabling paredit-mode, the prefix to this code that
  ;; DEFINE-MINOR-MODE inserts will have already set PAREDIT-MODE to
  ;; true.  If this is the case, then first check the parentheses, and
  ;; if there are any imbalanced ones we must inhibit the activation of
  ;; paredit mode.  We skip the check, though, if the user supplied a
  ;; prefix argument interactively.
  (if (and paredit-mode
	   (not current-prefix-arg))
      (if (not (fboundp 'check-parens))
	  (paredit-warn "`check-parens' is not defined; %s"
			 "be careful of malformed S-expressions.")
	(condition-case condition
	    (progn
	      (check-parens)
	      (add-hook 'after-save-hook 'check-parens t t))
	  (error (setq paredit-mode nil)
		 (signal (car condition) (cdr condition)))))))

;;; Old functions from when there was a different mode for emacs -nw.

(defun turn-on-paredit-mode ()
  "Turn on pseudo-structural editing of Lisp code.

Deprecated: use `paredit-mode' instead."
  (interactive)
  (paredit-mode +1))

(defun turn-off-paredit-mode ()
  "Turn off pseudo-structural editing of Lisp code.

Deprecated: use `paredit-mode' instead."
  (interactive)
  (paredit-mode -1))

(defvar paredit-backward-delete-key
  (xcond ((paredit-xemacs-p)    "BS")
	 ((paredit-gnu-emacs-p) "DEL")))

(defvar paredit-forward-delete-keys
  (xcond ((paredit-xemacs-p)    '("DEL"))
	 ((paredit-gnu-emacs-p) '("<delete>" "<deletechar>"))))

;;;; Paredit Keys

;;; Separating the definition and initialization of this variable
;;; simplifies the development of paredit, since re-evaluating DEFVAR
;;; forms doesn't actually do anything.

(defvar paredit-commands nil
  "List of paredit commands with their keys and examples.")

;;; Each specifier is of the form:
;;;   (key[s] function (example-input example-output) ...)
;;; where key[s] is either a single string suitable for passing to KBD
;;; or a list of such strings.  Entries in this list may also just be
;;; strings, in which case they are headings for the next entries.

(progn
  (setq paredit-commands
	`(
	  "Basic Insertion Commands"
	  ("("         paredit-open-parenthesis
	   ("(a b |c d)"
	    "(a b (|) c d)")
	   ("(foo \"bar |baz\" quux)"
	    "(foo \"bar (|baz\" quux)"))
	  ("M-)"       paredit-close-parenthesis
	   ("(defun f (x|  ))"
	    "(defun f (x)\n  |)")
	   ("; (Foo.|"
	    "; (Foo.)|"))
	  (")"         paredit-close-parenthesis-and-newline
	   ("(a b |c   )" "(a b c)|")
	   ("; Hello,| world!"
	    "; Hello,)| world!"))
	  ("["         paredit-open-bracket
	   ("(a b |c d)"
	    "(a b [|] c d)")
	   ("(foo \"bar |baz\" quux)"
	    "(foo \"bar [baz\" quux)"))
	  ("]"         paredit-close-bracket
	   ("(define-key keymap [frob|  ] 'frobnicate)"
	    "(define-key keymap [frob]| 'frobnicate)")
	   ("; [Bar.|"
	    "; [Bar.]|"))
	  ("\""        paredit-doublequote
	   ("(frob grovel |full lexical)"
	    "(frob grovel \"|\" full lexical)")
	   ("(foo \"bar |baz\" quux)"
	    "(foo \"bar \\\"|baz\" quux)"))
	  ("M-\""      paredit-meta-doublequote
	   ("(foo \"bar |baz\" quux)"
	    "(foo \"bar baz\"\n     |quux)")
	   ("(foo |(bar #\\x \"baz \\\\ quux\") zot)"
	    ,(concat "(foo \"|(bar #\\\\x \\\"baz \\\\"
		     "\\\\ quux\\\")\" zot)")))
	  ("\\"        paredit-backslash
	   ("(string #|)\n  ; Escaping character... (x)"
	    "(string #\\x|)")
	   ("\"foo|bar\"\n  ; Escaping character... (\")"
	    "\"foo\\\"|bar\""))
	  (";"         paredit-semicolon
	   ("|(frob grovel)"
	    ";|\n(frob grovel)")
	   ("(frob grovel)    |"
	    "(frob grovel)    ;|"))
	  ("M-;"       paredit-comment-dwim
	   ("(foo |bar)   ; baz"
	    "(foo bar)                               ; |baz")
	   ("(frob grovel)|"
	    "(frob grovel)                           ;|")
	   ("    (foo bar)\n|\n    (baz quux)"
	    "    (foo bar)\n    ;; |\n    (baz quux)")
	   ("    (foo bar) |(baz quux)"
	    "    (foo bar)\n    ;; |\n    (baz quux)")
	   ("|(defun hello-world ...)"
	    ";;; |\n(defun hello-world ...)"))
	  
	  ("C-j"       paredit-newline
	   ("(let ((n (frobbotz))) |(display (+ n 1)\nport))"
	    ,(concat "(let ((n (frobbotz)))"
		     "\n  |(display (+ n 1)"
		     "\n            port))")))

	  ("TAB"       paredit-indent-and-complete-symbol)
	  ("M-q"       paredit-reindent-defun)

	  "Deleting & Killing"
	  (("C-d" ,@paredit-forward-delete-keys)
	   paredit-forward-delete
	   ("(quu|x \"zot\")" "(quu| \"zot\")")
	   ("(quux |\"zot\")"
	    "(quux \"|zot\")"
	    "(quux \"|ot\")")
	   ("(foo (|) bar)" "(foo | bar)")
	   ("|(foo bar)" "(|foo bar)"))
	  (,paredit-backward-delete-key
	   paredit-backward-delete
	   ("(\"zot\" q|uux)" "(\"zot\" |uux)")
	   ("(\"zot\"| quux)"
	    "(\"zot|\" quux)"
	    "(\"zo|\" quux)")
	   ("(foo (|) bar)" "(foo | bar)")
	   ("(foo bar)|" "(foo bar|)"))
	  ("C-k"       paredit-kill
	   ("(foo bar)|     ; Useless comment!"
	    "(foo bar)|")
	   ("(|foo bar)     ; Useful comment!"
	    "(|)     ; Useful comment!")
	   ("|(foo bar)     ; Useless line!"
	    "|")
	   ("(foo \"|bar baz\"\n     quux)"
	    "(foo \"|\"\n     quux)"))
	  ("M-d"       paredit-forward-kill-word
	   ("|(foo bar)    ; baz"
	    "(| bar)    ; baz"
	    "(|)    ; baz"
	    "()    ;|")
	   (";;;| Frobnicate\n(defun frobnicate ...)"
	    ";;;|\n(defun frobnicate ...)"
	    ";;;\n(| frobnicate ...)"))
	  (,(concat "M-" paredit-backward-delete-key)
	   paredit-backward-kill-word
	   ("(foo bar)    ; baz\n(quux)|"
	    "(foo bar)    ; baz\n(|)"
	    "(foo bar)    ; |\n()"
	    "(foo |)    ; \n()"
	    "(|)    ; \n()"))

	  "Movement & Navigation"
	  ("C-M-f"     paredit-forward
	   ("(foo |(bar baz) quux)"
	    "(foo (bar baz)| quux)")
	   ("(foo (bar)|)"
	    "(foo (bar))|"))
	  ("C-M-b"     paredit-backward
	   ("(foo (bar baz)| quux)"
	    "(foo |(bar baz) quux)")
	   ("(|(foo) bar)"
	    "|((foo) bar)"))
;;;("C-M-u"     backward-up-list)       ; These two are built-in.
;;;("C-M-d"     down-list)
	  ("C-M-p"     backward-down-list)	; Built-in, these are FORWARD-
	  ("C-M-n"     up-list)			; & BACKWARD-LIST, which have
                                        ; no need given C-M-f & C-M-b.
	  
	  "Depth-Changing Commands"
	  ("M-("       paredit-wrap-sexp
	   ("(foo |bar baz)"
	    "(foo (|bar) baz)"))
	  ("M-s"       paredit-splice-sexp
	   ("(foo (bar| baz) quux)"
	    "(foo bar| baz quux)"))
	  (("M-<up>" "ESC <up>")
	   paredit-splice-sexp-killing-backward
	   ("(foo (let ((x 5)) |(sqrt n)) bar)"
	    "(foo (sqrt n) bar)"))
	  (("M-<down>" "ESC <down>")
	   paredit-splice-sexp-killing-forward
	   ("(a (b c| d e) f)"
	    "(a b c f)"))
	  ("M-g"       paredit-raise-sexp
	   ("(dynamic-wind in (lambda () |body) out)"
	    "(dynamic-wind in |body out)"
	    "|body"))

	  "Barfage & Slurpage"
	  (("C-)" "C-<right>")
	   paredit-forward-slurp-sexp
	   ("(foo (bar |baz) quux zot)"
	    "(foo (bar |baz quux) zot)")
	   ("(a b ((c| d)) e f)"
	    "(a b ((c| d) e) f)"))
	  (("C-}" "C-<left>")
	   paredit-forward-barf-sexp
	   ("(foo (bar |baz quux) zot)"
	    "(foo (bar |baz) quux zot)"))
	  ("C-M-)"
	   paredit-forward-join-sexp
	   ("(foo (bar |baz) (quux) zot)"
	    "(foo (bar |baz quux) zot)")
	   ("(a b ((c| d)) (e) f)"
	    "(a b ((c| d) e) f)"))
	  ("C-M-}"
	   paredit-forward-leave-sexp
	   ("(foo (bar |baz quux) zot)"
	    "(foo (bar |baz) (quux) zot)"))
	  (("C-(" "C-M-<left>" "ESC C-<left>")
	   paredit-backward-slurp-sexp
	   ("(foo bar (baz| quux) zot)"
	    "(foo (bar baz| quux) zot)")
	   ("(a b ((c| d)) e f)"
	    "(a (b (c| d)) e f)"))
	  ("C-M-("
	   paredit-backward-join-sexp
	   ("(foo (bar) (baz| quux) zot)"
	    "(foo (bar baz| quux) zot)")
	   ("(a (b) ((c| d)) e f)"
	    "(a (b (c| d)) e f)"))
	  (("C-{" "C-M-<right>" "ESC C-<right>")
	   paredit-backward-barf-sexp
	   ("(foo (bar baz |quux) zot)"
	    "(foo bar (baz |quux) zot)"))
	  ("C-M-{"
	   paredit-backward-leave-sexp
	   ("(foo (bar baz |quux) zot)"
	    "(foo (bar) (baz |quux) zot)"))

	  "Miscellaneous Commands"
	  ("M-S"       paredit-split-sexp
	   ("(hello| world)"
	    "(hello)| (world)")
	   ("\"Hello, |world!\""
	    "\"Hello, \"| \"world!\""))
	  ("M-J"       paredit-join-sexps
	   ("(hello)| (world)"
	    "(hello| world)")
	   ("\"Hello, \"| \"world!\""
	    "\"Hello, |world!\"")
	   ("hello-\n|  world"
	    "hello-|world"))
	  ("C-c M-l" paredit-refactor-let)
	  ("C-c M-f" paredit-refactor-flet)
	  ("C-c M-c" paredit-convolute-up-sexp)
	  ("C-c C-l" paredit-recentre-on-sexp)
	  ))
  nil)					; end of PROGN

;;;;; Command Examples

(eval-and-compile
  (defmacro paredit-do-commands (vars string-case &rest body)
    (let ((spec     (nth 0 vars))
	  (keys     (nth 1 vars))
	  (fn       (nth 2 vars))
	  (examples (nth 3 vars)))
      `(dolist (,spec paredit-commands)
	 (if (stringp ,spec)
	     ,string-case
	   (let ((,keys (let ((k (car ,spec)))
			  (cond ((stringp k) (list k))
				((listp k) k)
				(t (error "Invalid paredit command %s."
					  ,spec)))))
		 (,fn (cadr ,spec))
		 (,examples (cddr ,spec)))
	     ,@body)))))

  (put 'paredit-do-commands 'lisp-indent-function 2))

(defun paredit-define-keys ()
  (paredit-do-commands (spec keys fn examples)
      nil				; string case
    (dolist (key keys)
      (define-key paredit-mode-map (read-kbd-macro key) fn))))

(defun paredit-function-documentation (fn)
  (let ((original-doc (get fn 'paredit-original-documentation))
	(doc (documentation fn 'function-documentation)))
    (or original-doc
	(progn (put fn 'paredit-original-documentation doc)
	       doc))))

(defun paredit-annotate-mode-with-examples ()
  (let ((contents
	 (list (paredit-function-documentation 'paredit-mode))))
    (paredit-do-commands (spec keys fn examples)
	(push (concat "\n\n" spec "\n")
	      contents)
      (let ((name (symbol-name fn)))
	(if (string-match (symbol-name 'paredit-) name)
	    (push (concat "\n\n\\[" name "]\t" name
			  (if examples
			      (mapconcat (lambda (example)
					   (concat
					    "\n"
					    (mapconcat 'identity
						       example
						       "\n  --->\n")
					    "\n"))
					 examples
					 "")
			    "\n  (no examples)\n"))
		  contents))))
    (put 'paredit-mode 'function-documentation
	 (apply 'concat (reverse contents))))
  ;; PUT returns the huge string we just constructed, which we don't
  ;; want it to return.
  nil)

(defun paredit-annotate-functions-with-examples ()
  (paredit-do-commands (spec keys fn examples)
      nil				; string case
    (put fn 'function-documentation
	 (concat (paredit-function-documentation fn)
		 "\n\n\\<paredit-mode-map>\\[" (symbol-name fn) "]\n"
		 (mapconcat (lambda (example)
			      (concat "\n"
				      (mapconcat 'identity
						 example
						 "\n  ->\n")
				      "\n"))
			    examples
			    "")))))

;;;;; HTML Examples

(defun paredit-insert-html-examples ()
  "Insert HTML for a paredit quick reference table."
  (interactive)
  (let ((insert-lines (lambda (&rest lines)
			(mapc (lambda (line) (insert line) (newline))
			      lines)))
	(html-keys (lambda (keys)
		     (mapconcat 'paredit-html-quote keys ", ")))
	(html-example
	 (lambda (example)
	   (concat "<table><tr><td><pre>"
		   (mapconcat 'paredit-html-quote
			      example
			      (concat "</pre></td></tr><tr><td>"
				      "&nbsp;&nbsp;&nbsp;&nbsp;---&gt;" ;
				      "</td></tr><tr><td><pre>"))
		   "</pre></td></tr></table>")))
	(firstp t))
    (paredit-do-commands (spec keys fn examples)
	(progn (if (not firstp)
		   (insert "</table>\n")
		 (setq firstp nil))
	       (funcall insert-lines
			(concat "<h3>" spec "</h3>")
			"<table border=\"1\" cellpadding=\"1\">"
			"  <tr>"
			"    <th>Command</th>"
			"    <th>Keys</th>"
			"    <th>Examples</th>"
			"  </tr>"))
      (let ((name (symbol-name fn)))
	(if (string-match (symbol-name 'paredit-) name)
	    (funcall insert-lines
		     "  <tr>"
		     (concat "    <td><tt>" name "</tt></td>")
		     (concat "    <td align=\"center\">"
			     (funcall html-keys keys)
			     "</td>")
		     (concat "    <td>"
			     (if examples
				 (mapconcat html-example examples
					    "<hr>")
			       "(no examples)")
			     "</td>")
		     "  </tr>")))))
  (insert "</table>\n"))

(defun paredit-html-quote (string)
  (with-temp-buffer
    (dotimes (i (length string))
      (insert (let ((c (elt string i)))
		(cond ((eq c ?\<) "&lt;")
		      ((eq c ?\>) "&gt;")
		      ((eq c ?\&) "&amp;")
		      ((eq c ?\') "&apos;")
		      ((eq c ?\") "&quot;")
		      (t c)))))
    (buffer-string)))

;;;; Delimiter Insertion

(eval-and-compile
  (defun paredit-conc-name (&rest strings)
    (intern (apply 'concat strings)))

  (defmacro define-paredit-pair (open close name)
    `(progn
       (defun ,(paredit-conc-name "paredit-open-" name) (&optional n)
	 ,(concat "Insert a balanced " name " pair.
With a prefix argument N, put the closing " name " after N
  S-expressions forward.
If the region is active, `transient-mark-mode' is enabled, and the
  region's start and end fall in the same parenthesis depth, insert a
  " name " pair around the region.
If in a string or a comment, insert a single " name ".
If in a character literal, do nothing.  This prevents changing what was
  in the character literal to a meaningful delimiter unintentionally.")
	 (interactive "P")
	 (cond ((or (paredit-in-string-p)
		    (paredit-in-comment-p))
		(insert ,open))
	       ((not (paredit-in-char-p))
		(paredit-insert-pair n ,open ,close 'goto-char))))
       (defun ,(paredit-conc-name "paredit-close-" name) ()
	 ,(concat "Move past one closing delimiter and reindent.
\(Agnostic to the specific closing delimiter.)
If in a string or comment, insert a single closing " name ".
If in a character literal, do nothing.  This prevents changing what was
  in the character literal to a meaningful delimiter unintentionally.")
	 (interactive)
	 (paredit-move-past-close ,close))
       (defun ,(paredit-conc-name "paredit-close-" name "-and-newline") ()
	 ,(concat "Move past one closing delimiter, add a newline,"
		  " and reindent.
If there was a margin comment after the closing delimiter, preserve it
  on the same line.")
	 (interactive)
	 (paredit-move-past-close-and-newline ,close)))))

(define-paredit-pair ?\( ?\) "parenthesis")
(define-paredit-pair ?\[ ?\] "bracket")
(define-paredit-pair ?\{ ?\} "brace")
(define-paredit-pair ?\< ?\> "brocket")

(defun paredit-move-past-close (close)
  (cond ((or (paredit-in-string-p)
	     (paredit-in-comment-p))
	 (insert close))
	((not (paredit-in-char-p))
	 (if (save-excursion
	       (backward-up-list)
	       (condition-case err
		   (ignore (paredit-forward))
		 (error t)))
	     (insert close)
	   (paredit-move-past-close-and-reindent)
	   (paredit-blink-paren-match nil)))))

(defun paredit-move-past-close-and-newline (close)
  (cond ((or (paredit-in-string-p)
	     (paredit-in-comment-p))
	 (insert close))
	(t (if (paredit-in-char-p) (forward-char))
	   (when (save-excursion
		   (backward-up-list)
		   (condition-case err
		       (ignore (paredit-forward))
		     (error t)))
	     (insert close)
	     (backward-char))
	   (paredit-move-past-close-and-reindent)
	   (let ((comment.point (paredit-find-comment-on-line)))
	     (newline)
	     (if comment.point
		 (save-excursion
		   (forward-line -1)
		   (end-of-line)
		   (indent-to (cdr comment.point))
		   (insert (car comment.point)))))
	   (lisp-indent-line)
	   (paredit-ignore-sexp-errors (indent-sexp))
	   ;;(paredit-blink-paren-match t)
	   )))

(defun paredit-find-comment-on-line ()
  "Find a margin comment on the current line.
If such a comment exists, delete the comment (including all leading
  whitespace) and return a cons whose car is the comment as a string
  and whose cdr is the point of the comment's initial semicolon,
  relative to the start of the line."
  (save-excursion
    (catch 'return
      (while t
	(if (search-forward ";" (point-at-eol) t)
	    (if (not (or (paredit-in-string-p)
			 (paredit-in-char-p)))
		(let* ((start (progn (backward-char) ;before semicolon
				     (point)))
		       (comment (buffer-substring start
						  (point-at-eol))))
		  (paredit-skip-whitespace nil (point-at-bol))
		  (delete-region (point) (point-at-eol))
		  (throw 'return
			 (cons comment (- start (point-at-bol))))))
	  (throw 'return nil))))))

(defun paredit-insert-pair (n open close forward)
  (let* ((regionp (and (paredit-region-active-p)
		       (paredit-region-safe-for-insert-p)))
	 (end (and regionp
		   (not n)
		   (prog1 (region-end)
		     (goto-char (region-beginning))))))
    (let ((spacep (paredit-space-for-delimiter-p nil open)))
      (if spacep (insert " "))
      (insert open)
      (save-excursion
	;; Move past the desired region.
	(cond (n (funcall forward
			  (save-excursion
			    (forward-sexp (prefix-numeric-value n))
			    (point))))
	      (regionp (funcall forward (+ end (if spacep 2 1)))))
	(insert close)
	(if (paredit-space-for-delimiter-p t close)
	    (insert " "))))))

(defun paredit-region-safe-for-insert-p ()
  (save-excursion
    (let ((beginning (region-beginning))
	  (end (region-end)))
      (goto-char beginning)
      (let* ((beginning-state (paredit-current-parse-state))
	     (end-state (parse-partial-sexp beginning end
					    nil nil beginning-state)))
	(and (=  (nth 0 beginning-state) ; 0. depth in parens
		 (nth 0 end-state))
	     (eq (nth 3 beginning-state) ; 3. non-nil if inside a
		 (nth 3 end-state))	 ;    string
	     (eq (nth 4 beginning-state) ; 4. comment status, yada
		 (nth 4 end-state))
	     (eq (nth 5 beginning-state) ; 5. t if following char
		 (nth 5 end-state))))))) ;    quote

(defun paredit-space-for-delimiter-p (endp delimiter)
  ;; If at the buffer limit, don't insert a space.  If there is a word,
  ;; symbol, other quote, or non-matching parenthesis delimiter (i.e. a
  ;; close when want an open the string or an open when we want to
  ;; close the string), do insert a space.
  (and (not (if endp (eobp) (bobp)))
       (memq (char-syntax (if endp
			      (char-after)
			    (char-before)))
	     (list ?w ?_ ?\"
		   (let ((matching (matching-paren delimiter)))
		     (and matching (char-syntax matching)))))))

(defun paredit-move-past-close-and-reindent ()
  (let ((orig (point)))
    (up-list)
    (if (catch 'return			; This CATCH returns T if it
	  (while t			; should delete leading spaces
	    (save-excursion		; and NIL if not.
	      (let ((before-paren (1- (point))))
		(back-to-indentation)
		(cond ((not (eq (point) before-paren))
		       ;; Can't call PAREDIT-DELETE-LEADING-WHITESPACE
		       ;; here -- we must return from SAVE-EXCURSION
		       ;; first.
		       (throw 'return t))
		      ((save-excursion (forward-line -1)
				       (end-of-line)
				       (paredit-in-comment-p))
		       ;; Moving the closing parenthesis any further
		       ;; would put it into a comment, so we just
		       ;; indent the closing parenthesis where it is
		       ;; and abort the loop, telling its continuation
		       ;; that no leading whitespace should be deleted.
		       (lisp-indent-line)
		       (throw 'return nil))
		      (t (delete-indentation)))))))
	(paredit-delete-leading-whitespace))))

(defun paredit-delete-leading-whitespace ()
  ;; This assumes that we're on the closing parenthesis already.
  (save-excursion
    (backward-char)
    (while (let ((syn (char-syntax (char-before))))
	     (and (or (eq syn ?\ ) (eq syn ?-)) ; whitespace syntax
		  ;; The above line is a perfect example of why the
		  ;; following test is necessary.
		  (not (paredit-in-char-p (1- (point))))))
      (backward-delete-char 1))))

(defun paredit-blink-paren-match (another-line-p)
  (if (and blink-matching-paren
	   (or (not show-paren-mode) another-line-p))
      (paredit-ignore-sexp-errors
	(save-excursion
	  (backward-sexp)
	  (forward-sexp)
	  ;; SHOW-PAREN-MODE inhibits any blinking, so we disable it
	  ;; locally here.
	  (let ((show-paren-mode nil))
	    (blink-matching-open))))))

(defun paredit-doublequote (&optional n)
  "Insert a pair of double-quotes.
With a prefix argument N, wrap the following N S-expressions in
  double-quotes, escaping intermediate characters if necessary.
If the region is active, `transient-mark-mode' is enabled, and the
  region's start and end fall in the same parenthesis depth, insert a
  pair of double-quotes around the region, again escaping intermediate
  characters if necessary.
Inside a comment, insert a literal double-quote.
At the end of a string, move past the closing double-quote.
In the middle of a string, insert a backslash-escaped double-quote.
If in a character literal, do nothing.  This prevents accidentally
  changing a what was in the character literal to become a meaningful
  delimiter unintentionally."
  (interactive "P")
  (cond ((paredit-in-string-p)
	 (if (eq (cdr (paredit-string-start+end-points))
		 (point))
	     (forward-char)		; We're on the closing quote.
	   (insert ?\\ ?\" )))
	((paredit-in-comment-p)
	 (insert ?\" ))
	((not (paredit-in-char-p))
	 (paredit-insert-pair n ?\" ?\" 'paredit-forward-for-quote))))

(defun paredit-meta-doublequote (&optional n)
  "Move to the end of the string, insert a newline, and indent.
If not in a string, act as `paredit-doublequote'; if no prefix argument
  is specified and the region is not active or `transient-mark-mode' is
  disabled, the default is to wrap one S-expression, however, not
  zero."
  (interactive "P")
  (if (not (paredit-in-string-p))
      (paredit-doublequote (or n
				(and (not (paredit-region-active-p))
				     1)))
    (let ((start+end (paredit-string-start+end-points)))
      (goto-char (1+ (cdr start+end)))
      (newline)
      (lisp-indent-line)
      (paredit-ignore-sexp-errors (indent-sexp)))))

(defun paredit-forward-for-quote (end)
  (let ((state (paredit-current-parse-state)))
    (while (< (point) end)
      (let ((new-state (parse-partial-sexp (point) (1+ (point))
					   nil nil state)))
	(if (paredit-in-string-p new-state)
	    (if (not (paredit-in-string-escape-p))
		(setq state new-state)
	      ;; Escape character: turn it into an escaped escape
	      ;; character by appending another backslash.
	      (insert ?\\ )
	      ;; Now the point is after both escapes, and we want to
	      ;; rescan from before the first one to after the second
	      ;; one.
	      (setq state
		    (parse-partial-sexp (- (point) 2) (point)
					nil nil state))
	      ;; Advance the end point, since we just inserted a new
	      ;; character.
	      (setq end (1+ end)))
	  ;; String: escape by inserting a backslash before the quote.
	  (backward-char)
	  (insert ?\\ )
	  ;; The point is now between the escape and the quote, and we
	  ;; want to rescan from before the escape to after the quote.
	  (setq state
		(parse-partial-sexp (1- (point)) (1+ (point))
				    nil nil state))
	  ;; Advance the end point for the same reason as above.
	  (setq end (1+ end)))))))

;;;; Escape Insertion

(defun paredit-backslash ()
  "Insert a backslash followed by a character to escape."
  (interactive)
  (insert ?\\ )
  ;; This funny conditional is necessary because PAREDIT-IN-COMMENT-P
  ;; assumes that PAREDIT-IN-STRING-P already returned false; otherwise
  ;; it may give erroneous answers.
  (if (or (paredit-in-string-p)
	  (not (paredit-in-comment-p)))
      (let ((delp t))
	(unwind-protect (setq delp
			      (call-interactively 'paredit-escape))
	  ;; We need this in an UNWIND-PROTECT so that the backlash is
	  ;; left in there *only* if PAREDIT-ESCAPE return NIL normally
	  ;; -- in any other case, such as the user hitting C-g or an
	  ;; error occurring, we must delete the backslash to avoid
	  ;; leaving a dangling escape.  (This control structure is a
	  ;; crock.)
	  (if delp (backward-delete-char 1))))))

;;; This auxiliary interactive function returns true if the backslash
;;; should be deleted and false if not.

(defun paredit-escape (char)
  ;; I'm too lazy to figure out how to do this without a separate
  ;; interactive function.
  (interactive "cEscaping character...")
  (if (eq char 127)			; The backslash was a typo, so
      t					; the luser wants to delete it.
    (insert char)			; (Is there a better way to
    nil))				; express the rubout char?
                                        ; ?\^? works, but ugh...)

;;; The placement of this function in this file is totally random.

(defun paredit-newline ()
  "Insert a newline and indent it.
This is like `newline-and-indent', but it not only indents the line
  that the point is on but also the S-expression following the point,
  if there is one.
Move forward one character first if on an escaped character.
If in a string, just insert a literal newline."
  (interactive)
  (if (paredit-in-string-p)
      (newline)
    (if (and (not (paredit-in-comment-p)) (paredit-in-char-p))
	(forward-char))
    (newline-and-indent)
    ;; Indent the following S-expression, but don't signal an error if
    ;; there's only a closing parenthesis after the point.
    (paredit-ignore-sexp-errors (indent-sexp))))

;;;; Comment Insertion

(defun paredit-semicolon (&optional n)
  "Insert a semicolon, moving any code after the point to a new line.
If in a string, comment, or character literal, insert just a literal
  semicolon, and do not move anything to the next line.
With a prefix argument N, insert N semicolons."
  (interactive "P")
  (if (not (or (paredit-in-string-p)
	       (paredit-in-comment-p)
	       (paredit-in-char-p)
	       ;; No more code on the line after the point.
	       (save-excursion
		 (paredit-skip-whitespace t (point-at-eol))
		 (or (eolp)
		     ;; Let the user prefix semicolons to existing
		     ;; comments.
		     (eq (char-after) ?\;)))))
      ;; Don't use NEWLINE-AND-INDENT, because that will delete all of
      ;; the horizontal whitespace first, but we just want to move the
      ;; code following the point onto the next line while preserving
      ;; the point on this line.
					;++ Why indent only the line?
      (save-excursion (newline) (lisp-indent-line)))
  (insert (make-string (if n (prefix-numeric-value n) 1)
		       ?\; )))

(defun paredit-comment-dwim (&optional arg)
  "Call the Lisp comment command you want (Do What I Mean).
This is like `comment-dwim', but it is specialized for Lisp editing.
If transient mark mode is enabled and the mark is active, comment or
  uncomment the selected region, depending on whether it was entirely
  commented not not already.
If there is already a comment on the current line, with no prefix
  argument, indent to that comment; with a prefix argument, kill that
  comment.
Otherwise, insert a comment appropriate for the context and ensure that
  any code following the comment is moved to the next line.
At the top level, where indentation is calculated to be at column 0,
  insert a triple-semicolon comment; within code, where the indentation
  is calculated to be non-zero, and on the line there is either no code
  at all or code after the point, insert a double-semicolon comment;
  and if the point is after all code on the line, insert a single-
  semicolon margin comment at `comment-column'."
  (interactive "*P")
  (require 'newcomment)
  (comment-normalize-vars)
  (cond ((paredit-region-active-p)
	 (comment-or-uncomment-region (region-beginning)
				      (region-end)
				      arg))
	((paredit-comment-on-line-p)
	 (if arg
	     (comment-kill (if (integerp arg) arg nil))
	   (comment-indent)))
	(t (paredit-insert-comment))))

(defun paredit-comment-on-line-p ()
  (save-excursion
    (beginning-of-line)
    (let ((comment-p nil))
      ;; Search forward for a comment beginning.  If there is one, set
      ;; COMMENT-P to true; if not, it will be nil.
      (while (progn (setq comment-p
			  (search-forward ";" (point-at-eol)
					  ;; t -> no error
					  t))
		    (and comment-p
			 (or (paredit-in-string-p)
			     (paredit-in-char-p (1- (point))))))
	(forward-char))
      comment-p)))

(defun paredit-insert-comment ()
  (let ((code-after-p
	 (save-excursion (paredit-skip-whitespace t (point-at-eol))
			 (not (eolp))))
	(code-before-p
	 (save-excursion (paredit-skip-whitespace nil (point-at-bol))
			 (not (bolp)))))
    (if (and (bolp)
	     ;; We have to use EQ 0 here and not ZEROP because ZEROP
	     ;; signals an error if its argument is non-numeric, but
	     ;; CALCULATE-LISP-INDENT may return nil.
	     (eq (let ((indent (calculate-lisp-indent)))
		   (if (consp indent)
		       (car indent)
		     indent))
		 0))
	;; Top-level comment
	(progn (if code-after-p (save-excursion (newline)))
	       (insert ";;; "))
      (if code-after-p
	  ;; Code comment
	  (progn (if code-before-p
					;++ Why NEWLINE-AND-INDENT here and not just
					;++ NEWLINE, or PAREDIT-NEWLINE?
		     (newline-and-indent))
		 (lisp-indent-line)
		 (insert ";; ")
		 ;; Move the following code.  (NEWLINE-AND-INDENT will
		 ;; delete whitespace after the comment, though, so use
		 ;; NEWLINE & LISP-INDENT-LINE manually here.)
		 (save-excursion (newline)
				 (lisp-indent-line)))
	;; Margin comment
	(progn (indent-to comment-column
			  1)		; 1 -> force one leading space
	       (insert ?\; ))))))

;;;; Character Deletion

(defun paredit-forward-delete (&optional arg)
  "Delete a character forward or move forward over a delimiter.
If on an opening S-expression delimiter, move forward into the
  S-expression.
If on a closing S-expression delimiter, refuse to delete unless the
  S-expression is empty, in which case delete the whole S-expression.
With a prefix argument, simply delete a character forward, without
  regard for delimiter balancing."
  (interactive "P")
  (cond ((or arg (eobp))
	 (delete-char 1))
	((paredit-in-string-p)
	 (paredit-forward-delete-in-string))
	((paredit-in-comment-p)
					;++ What to do here?  This could move a partial S-expression
					;++ into a comment and thereby invalidate the file's form,
					;++ or move random text out of a comment.
	 (delete-char 1))
	((paredit-in-char-p)		; Escape -- delete both chars.
	 (backward-delete-char 1)
	 (delete-char 1))
	((eq (char-after) ?\\ )		; ditto
	 (delete-char 2))
	((let ((syn (char-syntax (char-after))))
	   (or (eq syn ?\( )
	       (eq syn ?\" )))
	 (forward-char))
	((and (not (paredit-in-char-p (1- (point))))
	      (eq (char-syntax (char-after)) ?\) )
	      (eq (char-before) (matching-paren (char-after))))
	 (backward-delete-char 1)	; Empty list -- delete both
	 (delete-char 1))		;   delimiters.
	;; Just delete a single character, if it's not a closing
	;; parenthesis.  (The character literal case is already
	;; handled by now.)
	((not (eq (char-syntax (char-after)) ?\) ))
	 (delete-char 1))))

(defun paredit-forward-delete-in-string ()
  (let ((start+end (paredit-string-start+end-points)))
    (cond ((not (eq (point) (cdr start+end)))
	   ;; If it's not the close-quote, it's safe to delete.  But
	   ;; first handle the case that we're in a string escape.
	   (cond ((paredit-in-string-escape-p)
		  ;; We're right after the backslash, so backward
		  ;; delete it before deleting the escaped character.
		  (backward-delete-char 1))
		 ((eq (char-after) ?\\ )
		  ;; If we're not in a string escape, but we are on a
		  ;; backslash, it must start the escape for the next
		  ;; character, so delete the backslash before deleting
		  ;; the next character.
		  (delete-char 1)))
	   (delete-char 1))
	  ((eq (1- (point)) (car start+end))
	   ;; If it is the close-quote, delete only if we're also right
	   ;; past the open-quote (i.e. it's empty), and then delete
	   ;; both quotes.  Otherwise we refuse to delete it.
	   (backward-delete-char 1)
	   (delete-char 1)))))

(defun paredit-backward-delete (&optional arg)
  "Delete a character backward or move backward over a delimiter.
If on a closing S-expression delimiter, move backward into the
  S-expression.
If on an opening S-expression delimiter, refuse to delete unless the
  S-expression is empty, in which case delete the whole S-expression.
With a prefix argument, simply delete a character backward, without
  regard for delimiter balancing."
  (interactive "P")
  (cond ((or arg (bobp))
	 (backward-delete-char 1))	;++ should this untabify?
	((paredit-in-string-p)
	 (paredit-backward-delete-in-string))
	((paredit-in-comment-p)
	 (backward-delete-char 1))
	((paredit-in-char-p)		; Escape -- delete both chars.
	 (backward-delete-char 1)
	 (delete-char 1))
	((paredit-in-char-p (1- (point)))
	 (backward-delete-char 2))	; ditto
	((let ((syn (char-syntax (char-before))))
	   (or (eq syn ?\) )
	       (eq syn ?\" )))
	 (if (save-excursion
	       (condition-case err
		   (ignore (paredit-backward))
		 (error t)))
	     (backward-delete-char 1)
	   (backward-char)))
	((and (eq (char-syntax (char-before)) ?\( )
	      (eq (char-after) (matching-paren (char-before))))
	 (backward-delete-char 1)	; Empty list -- delete both
	 (delete-char 1))		;   delimiters.
	;; Delete it, unless it's an opening parenthesis.  The case
	;; of character literals is already handled by now.
	((not (eq (char-syntax (char-before)) ?\( ))
	 (backward-delete-char-untabify 1))))

(defun paredit-backward-delete-in-string ()
  (let ((start+end (paredit-string-start+end-points)))
    (cond ((not (eq (1- (point)) (car start+end)))
	   ;; If it's not the open-quote, it's safe to delete.
	   (if (paredit-in-string-escape-p)
	       ;; If we're on a string escape, since we're about to
	       ;; delete the backslash, we must first delete the
	       ;; escaped char.
	       (delete-char 1))
	   (backward-delete-char 1)
	   (if (paredit-in-string-escape-p)
	       ;; If, after deleting a character, we find ourselves in
	       ;; a string escape, we must have deleted the escaped
	       ;; character, and the backslash is behind the point, so
	       ;; backward delete it.
	       (backward-delete-char 1)))
	  ((eq (point) (cdr start+end))
	   ;; If it is the open-quote, delete only if we're also right
	   ;; past the close-quote (i.e. it's empty), and then delete
	   ;; both quotes.  Otherwise we refuse to delete it.
	   (backward-delete-char 1)
	   (delete-char 1)))))

;;;; Killing

(defun paredit-kill (&optional arg)
  "Kill a line as if with `kill-line', but respecting delimiters.
In a string, act exactly as `kill-line' but do not kill past the
  closing string delimiter.
On a line with no S-expressions on it starting after the point or
  within a comment, act exactly as `kill-line'.
Otherwise, kill all S-expressions that start after the point."
  (interactive "P")
  (cond (arg (kill-line))
	((paredit-in-string-p)
	 (paredit-kill-line-in-string))
	((or (paredit-in-comment-p)
	     (save-excursion
	       (paredit-skip-whitespace t (point-at-eol))
	       (or (eq (char-after) ?\; )
		   (eolp))))
					;** Be careful about trailing backslashes.
	 (kill-line))
	(t (paredit-kill-sexps-on-line))))

(defun paredit-kill-line-in-string ()
  (if (save-excursion (paredit-skip-whitespace t (point-at-eol))
		      (eolp))
      (kill-line)
    (save-excursion
      ;; Be careful not to split an escape sequence.
      (if (paredit-in-string-escape-p)
	  (backward-char))
      (let ((beginning (point)))
	(while (not (or (eolp)
			(eq (char-after) ?\" )))
	  (forward-char)
	  ;; Skip past escaped characters.
	  (if (eq (char-before) ?\\ )
	      (forward-char)))
	(kill-region beginning (point))))))

(defun paredit-kill-sexps-on-line ()
  (if (paredit-in-char-p)		; Move past the \ and prefix.
      (backward-char 2))		; (# in Scheme/CL, ? in elisp)
  (let ((beginning (point))
	(eol (point-at-eol)))
    (let ((end-of-list-p (paredit-forward-sexps-to-kill beginning eol)))
      ;; If we got to the end of the list and it's on the same line,
      ;; move backward past the closing delimiter before killing.  (This
      ;; allows something like killing the whitespace in (    ).)
      (if end-of-list-p (progn (up-list) (backward-char)))
      (if kill-whole-line
	  (paredit-kill-sexps-on-whole-line beginning)
	(kill-region beginning
		     ;; If all of the S-expressions were on one line,
		     ;; i.e. we're still on that line after moving past
		     ;; the last one, kill the whole line, including
		     ;; any comments; otherwise just kill to the end of
		     ;; the last S-expression we found.  Be sure,
		     ;; though, not to kill any closing parentheses.
		     (if (and (not end-of-list-p)
			      (eq (point-at-eol) eol))
			 eol
		       (point)))))))

;;; Please do not try to understand this code unless you have a VERY
;;; good reason to do so.  I gave up trying to figure it out well
;;; enough to explain it, long ago.

(defun paredit-forward-sexps-to-kill (beginning eol)
  (let ((end-of-list-p nil)
	(firstp t))
    ;; Move to the end of the last S-expression that started on this
    ;; line, or to the closing delimiter if the last S-expression in
    ;; this list is on the line.
    (catch 'return
      (while t
	;; This and the `kill-whole-line' business below fix a bug that
	;; inhibited any S-expression at the very end of the buffer
	;; (with no trailing newline) from being deleted.  It's a
	;; bizarre fix that I ought to document at some point, but I am
	;; too busy at the moment to do so.
	(if (and kill-whole-line (eobp)) (throw 'return nil))
	(save-excursion
	  (paredit-handle-sexp-errors (forward-sexp)
	    (up-list)
	    (setq end-of-list-p (eq (point-at-eol) eol))
	    (throw 'return nil))
	  (if (or (and (not firstp)
		       (not kill-whole-line)
		       (eobp))
		  (paredit-handle-sexp-errors
		      (progn (backward-sexp) nil)
		    t)
		  (not (eq (point-at-eol) eol)))
	      (throw 'return nil)))
	(forward-sexp)
	(if (and firstp
		 (not kill-whole-line)
		 (eobp))
	    (throw 'return nil))
	(setq firstp nil)))
    end-of-list-p))

(defun paredit-kill-sexps-on-whole-line (beginning)
  (kill-region beginning
	       (or (save-excursion	; Delete trailing indentation...
		     (paredit-skip-whitespace t)
		     (and (not (eq (char-after) ?\; ))
			  (point)))
		   ;; ...or just use the point past the newline, if
		   ;; we encounter a comment.
		   (point-at-eol)))
  (cond ((save-excursion (paredit-skip-whitespace nil (point-at-bol))
			 (bolp))
	 ;; Nothing but indentation before the point, so indent it.
	 (lisp-indent-line))
	((eobp) nil)		  ; Protect the CHAR-SYNTAX below against NIL.
	;; Insert a space to avoid invalid joining if necessary.
	((let ((syn-before (char-syntax (char-before)))
	       (syn-after  (char-syntax (char-after))))
	   (or (and (eq syn-before ?\) ) ; Separate opposing
		    (eq syn-after  ?\( )) ;   parentheses,
	       (and (eq syn-before ?\" )  ; string delimiter
		    (eq syn-after  ?\" )) ;   pairs,
	       (and (memq syn-before '(?_ ?w)) ; or word or symbol
		    (memq syn-after  '(?_ ?w))))) ;   constituents.
	 (insert " "))))

;;;;; Killing Words

;;; This is tricky and asymmetrical because backward parsing is
;;; extraordinarily difficult or impossible, so we have to implement
;;; killing in both directions by parsing forward.

(defun paredit-forward-kill-word ()
  "Kill a word forward, skipping over intervening delimiters."
  (interactive)
  (let ((beginning (point)))
    (skip-syntax-forward " -")
    (let* ((parse-state (paredit-current-parse-state))
	   (state (paredit-kill-word-state parse-state 'char-after)))
      (while (not (or (eobp)
		      (eq ?w (char-syntax (char-after)))))
	(setq parse-state
	      (progn (forward-char 1) (paredit-current-parse-state))
	      ;;               (parse-partial-sexp (point) (1+ (point))
	      ;;                                   nil nil parse-state)
	      )
	(let* ((old-state state)
	       (new-state
		(paredit-kill-word-state parse-state 'char-after)))
	  (cond ((not (eq old-state new-state))
		 (setq parse-state
		       (paredit-kill-word-hack old-state
						new-state
						parse-state))
		 (setq state
		       (paredit-kill-word-state parse-state
						 'char-after))
		 (setq beginning (point)))))))
    (goto-char beginning)
    (kill-word 1)))

(defun paredit-backward-kill-word ()
  "Kill a word backward, skipping over any intervening delimiters."
  (interactive)
  (if (not (or (bobp)
	       (eq (char-syntax (char-before)) ?w)))
      (let ((end (point)))
	(backward-word 1)
	(forward-word 1)
	(goto-char (min end (point)))
	(let* ((parse-state (paredit-current-parse-state))
	       (state
		(paredit-kill-word-state parse-state 'char-before)))
	  (while (and (< (point) end)
		      (progn
			(setq parse-state
			      (parse-partial-sexp (point) (1+ (point))
						  nil nil parse-state))
			(or (eq state
				(paredit-kill-word-state parse-state
							  'char-before))
			    (progn (backward-char 1) nil)))))
	  (if (and (eq state 'comment)
		   (eq ?\# (char-after (point)))
		   (eq ?\| (char-before (point))))
	      (backward-char 1)))))
  (backward-kill-word 1))

;;; Word-Killing Auxiliaries

(defun paredit-kill-word-state (parse-state adjacent-char-fn)
  (cond ((paredit-in-comment-p parse-state) 'comment)
	((paredit-in-string-p  parse-state) 'string)
	((memq (char-syntax (funcall adjacent-char-fn))
	       '(?\( ?\) ))
	 'delimiter)
	(t 'other)))

;;; This optionally advances the point past any comment delimiters that
;;; should probably not be touched, based on the last state change and
;;; the characters around the point.  It returns a new parse state,
;;; starting from the PARSE-STATE parameter.

(defun paredit-kill-word-hack (old-state new-state parse-state)
  (cond ((and (not (eq old-state 'comment))
	      (not (eq new-state 'comment))
	      (not (paredit-in-string-escape-p))
	      (eq ?\# (char-before))
	      (eq ?\| (char-after)))
	 (forward-char 1)
	 (paredit-current-parse-state)
	 ;;          (parse-partial-sexp (point) (1+ (point))
	 ;;                              nil nil parse-state)
	 )
	((and (not (eq old-state 'comment))
	      (eq new-state 'comment)
	      (eq ?\; (char-before)))
	 (skip-chars-forward ";")
	 (paredit-current-parse-state)
	 ;;          (parse-partial-sexp (point) (save-excursion
	 ;;                                        (skip-chars-forward ";"))
	 ;;                              nil nil parse-state)
	 )
	(t parse-state)))

;;;; Cursor and Screen Movement

(eval-and-compile
  (defmacro defun-saving-mark (name bvl doc &rest body)
    `(defun ,name ,bvl
       ,doc
       ,(xcond ((paredit-xemacs-p)
		'(interactive "_"))
	       ((paredit-gnu-emacs-p)
		'(interactive)))
       ,@body)))

(defun-saving-mark paredit-forward ()
  "Move forward an S-expression, or up an S-expression forward.
If there are no more S-expressions in this one before the closing
  delimiter, move past that closing delimiter; otherwise, move forward
  past the S-expression following the point."
  (paredit-handle-sexp-errors
      (forward-sexp)
					;++ Is it necessary to use UP-LIST and not just FORWARD-CHAR?
    (if (paredit-in-string-p) (forward-char) (up-list))))

(defun-saving-mark paredit-backward ()
  "Move backward an S-expression, or up an S-expression backward.
If there are no more S-expressions in this one before the opening
  delimiter, move past that opening delimiter backward; otherwise, move
  move backward past the S-expression preceding the point."
  (paredit-handle-sexp-errors
      (backward-sexp)
    (if (paredit-in-string-p) (backward-char) (backward-up-list))))

;;; Why is this not in lisp.el?

(defun backward-down-list (&optional arg)
  "Move backward and descend into one level of parentheses.
With ARG, do this that many times.
A negative argument means move forward but still descend a level."
  (interactive "p")
  (down-list (- (or arg 1))))

;;; Thanks to Marco Baringer for suggesting & writing this function.

(defun paredit-recentre-on-sexp (&optional n)
  "Recentre the screen on the S-expression following the point.
With a prefix argument N, encompass all N S-expressions forward."
  (interactive "P")
  (save-excursion
    (forward-sexp n)
    (let ((end-point (point)))
      (backward-sexp n)
      (let* ((start-point (point))
	     (start-line (count-lines (point-min) (point)))
	     (lines-on-sexps (count-lines start-point end-point)))
	(goto-line (+ start-line (/ lines-on-sexps 2)))
	(recenter)))))

;;;; Depth-Changing Commands:  Wrapping, Splicing, & Raising

(defun paredit-wrap-sexp (&optional n)
  "Wrap the following S-expression in a list.
If a prefix argument N is given, wrap N S-expressions.
Automatically indent the newly wrapped S-expression.
As a special case, if the point is at the end of a list, simply insert
  a pair of parentheses, rather than insert a lone opening parenthesis
  and then signal an error, in the interest of preserving structure."
  (interactive "P")
  (paredit-handle-sexp-errors
      (paredit-insert-pair (or n
				(and (not (paredit-region-active-p))
				     1))
			    ?\( ?\)
			    'goto-char)
    (insert ?\) )
    (backward-char))
  (save-excursion (backward-up-list) (indent-sexp)))

;;; Thanks to Marco Baringer for the suggestion of a prefix argument
;;; for PAREDIT-SPLICE-SEXP.  (I, Taylor R. Campbell, however, still
;;; implemented it, in case any of you lawyer-folk get confused by the
;;; remark in the top of the file about explicitly noting code written
;;; by other people.)

(defun paredit-splice-sexp (&optional arg)
  "Splice the list that the point is on by removing its delimiters.
With a prefix argument as in `C-u', kill all S-expressions backward in
  the current list before splicing all S-expressions forward into the
  enclosing list.
With two prefix arguments as in `C-u C-u', kill all S-expressions
  forward in the current list before splicing all S-expressions
  backward into the enclosing list.
With a numerical prefix argument N, kill N S-expressions backward in
  the current list before splicing the remaining S-expressions into the
  enclosing list.  If N is negative, kill forward.
This always creates a new entry on the kill ring."
  (interactive "P")
  (save-excursion
    (paredit-kill-surrounding-sexps-for-splice arg)
    (backward-up-list)			; Go up to the beginning...
    (save-excursion
      (forward-sexp)			; Go forward an expression, to
      (backward-delete-char 1))		;   delete the end delimiter.
    (delete-char 1)			; ...to delete the open char.
    (paredit-ignore-sexp-errors
      (backward-up-list)		; Reindent, now that the
      (indent-sexp))))			;   structure has changed.

(defun paredit-kill-surrounding-sexps-for-splice (arg)
  (cond ((paredit-in-string-p) (error "Splicing illegal in strings."))
	((or (not arg) (eq arg 0)) nil)
	((or (numberp arg) (eq arg '-))
	 ;; Kill ARG S-expressions before/after the point by saving
	 ;; the point, moving across them, and killing the region.
	 (let* ((arg (if (eq arg '-) -1 arg))
		(saved (paredit-point-at-sexp-boundary (- arg))))
	   (paredit-ignore-sexp-errors (backward-sexp arg))
	   (kill-region-new saved (point))))
	((consp arg)
	 (let ((v (car arg)))
	   (if (= v 4)			; one prefix argument
	       ;; Move backward until we hit the open paren; then
	       ;; kill that selected region.
	       (let ((end (paredit-point-at-sexp-start)))
		 (paredit-ignore-sexp-errors
		   (while (not (bobp))
		     (backward-sexp)))
		 (kill-region-new (point) end))
	     ;; Move forward until we hit the close paren; then
	     ;; kill that selected region.
	     (let ((beginning (paredit-point-at-sexp-end)))
	       (paredit-ignore-sexp-errors
		 (while (not (eobp))
		   (forward-sexp)))
	       (kill-region-new beginning (point))))))
	(t (error "Bizarre prefix argument: %s" arg))))

(defun paredit-splice-sexp-killing-backward (&optional n)
  "Splice the list the point is on by removing its delimiters, and
  also kill all S-expressions before the point in the current list.
With a prefix argument N, kill only the preceding N S-expressions."
  (interactive "P")
  (paredit-splice-sexp (if n
			    (prefix-numeric-value n)
			  '(4))))

(defun paredit-splice-sexp-killing-forward (&optional n)
  "Splice the list the point is on by removing its delimiters, and
  also kill all S-expressions after the point in the current list.
With a prefix argument N, kill only the following N S-expressions."
  (interactive "P")
  (paredit-splice-sexp (if n
			    (- (prefix-numeric-value n))
			  '(16))))

(defun paredit-raise-sexp (&optional n)
  "Raise the following S-expression in a tree, deleting its siblings.
With a prefix argument N, raise the following N S-expressions.  If N
  is negative, raise the preceding N S-expressions."
  (interactive "p")
  ;; Select the S-expressions we want to raise in a buffer substring.
  (let* ((bound (save-excursion (forward-sexp n) (point)))
	 (sexps (save-excursion		;++ Is this necessary?
		  (if (and n (< n 0))
		      (buffer-substring bound
					(paredit-point-at-sexp-end))
		    (buffer-substring (paredit-point-at-sexp-start)
				      bound)))))
    ;; Move up to the list we're raising those S-expressions out of and
    ;; delete it.
    (backward-up-list)
    (delete-region (point) (save-excursion (forward-sexp) (point)))
    (save-excursion (insert sexps))	; Insert & reindent the sexps.
    (save-excursion (let ((n (abs (or n 1))))
		      (while (> n 0)
			(paredit-forward-and-indent)
			(setq n (1- n)))))))

;;;; Slurpage & Barfage, Adopting & Orphaning

(defun paredit-forward-slurp-sexp ()
  "Add the S-expression following the current list into that list
  by moving the closing delimiter.
Automatically reindent the newly slurped S-expression with respect to
  its new enclosing form.
If in a string, move the opening double-quote forward by one
  S-expression and escape any intervening characters as necessary,
  without altering any indentation or formatting."
  (interactive)
  (save-excursion
    (cond ((or (paredit-in-comment-p)
	       (paredit-in-char-p))
	   (error "Invalid context for slurpage"))
	  ((paredit-in-string-p)
	   (paredit-forward-slurp-into-string))
	  (t
	   (paredit-forward-slurp-into-list)))))

(defun paredit-forward-slurp-into-list ()
  (up-list)				; Up to the end of the list to
  (let ((close (char-before)))		;   save and delete the closing
    (backward-delete-char 1)		;   delimiter.
    (catch 'return			; Go to the end of the desired
      (while t				;   S-expression, going up a
	(paredit-handle-sexp-errors	;   list if it's not in this,
	    (progn (paredit-forward-and-indent)
		   (throw 'return nil))
	  (up-list))))
    (insert close)))			; to insert that delimiter.

(defun paredit-forward-slurp-into-string ()
  (goto-char (1+ (cdr (paredit-string-start+end-points))))
  ;; Signal any errors that we might get first, before mucking with the
  ;; buffer's contents.
  (save-excursion (forward-sexp))
  (let ((close (char-before)))
    (backward-delete-char 1)
    (paredit-forward-for-quote (save-excursion (forward-sexp) (point)))
    (insert close)))

(defun paredit-forward-adopt-sexp ()
  "Add the contents of the S-expression following the current list into
  that list by moving the closing delimiter and removing parentheses.
Automatically reindent the newly adopted S-expression with respect to
  its new enclosing form.
If in a string, it is simply slurped."
  (interactive)
  (save-excursion
    (cond ((or (paredit-in-comment-p)
	       (paredit-in-char-p))
	   (error "Invalid context for adopting"))
	  ((paredit-in-string-p)
	   (paredit-forward-slurp-into-string))
	  (t
	   (paredit-forward-adopt-into-list)))))

(defun paredit-forward-adopt-into-list ()
  (up-list)				; Up to the end of the list to
  (paredit-join-sexps))

(defun paredit-forward-join-sexp ()
  (interactive)
  (save-excursion
    (cond ((or (paredit-in-comment-p)
	       (paredit-in-char-p)
	       (paredit-in-string-p))
	   (error "Invalid context for joining"))
	  (t
	   (save-excursion
	     (backward-up-list)
	     (forward-sexp)
	     (down-list)
	     (paredit-backward-slurp-sexp))))))

(defun paredit-forward-barf-sexp ()
  "Remove the last S-expression in the current list from that list
  by moving the closing delimiter.
Automatically reindent the newly barfed S-expression with respect to
  its new enclosing form."
  (interactive)
  (save-excursion
    (up-list)				; Up to the end of the list to
    (let ((close (char-before)))	;   save and delete the closing
      (backward-delete-char 1)		;   delimiter.
      (paredit-ignore-sexp-errors	; Go back to where we want to
	(backward-sexp))		;   insert the delimiter.
      (paredit-skip-whitespace nil)	; Skip leading whitespace.
      (cond ((bobp)
	     (error "Barfing all subexpressions with no open-paren?"))
	    ((paredit-in-comment-p)	; Don't put the close-paren in
	     (newline-and-indent)))	;   a comment.
      (insert close))
    ;; Reindent all of the newly barfed S-expressions.
    (paredit-forward-and-indent)))

(defun paredit-forward-orphan-sexp ()
  "Remove the last S-expression in the current list from that list
  by moving the closing delimiter and splicing its contents.
Automatically reindent the newly barfed S-expression with respect to
  its new enclosing form."
  (interactive)
  (save-excursion
    (up-list)				; Up to the end of the list to
    (backward-char)
    (paredit-backward)
    (paredit-split-sexp)))

(defun paredit-forward-leave-sexp ()
  (interactive)
  (save-excursion
    (cond ((or (paredit-in-comment-p)
	       (paredit-in-char-p)
	       (paredit-in-string-p))
	   (error "Invalid context for joining"))
	  (t
	   (save-excursion
	     (backward-up-list 2)
	     (paredit-forward-barf-sexp))))))

(defun paredit-backward-slurp-sexp ()
  "Add the S-expression preceding the current list into that list
  by moving the closing delimiter.
Automatically reindent the whole form into which new S-expression was
  slurped.
If in a string, move the opening double-quote backward by one
  S-expression and escape any intervening characters as necessary,
  without altering any indentation or formatting."
  (interactive)
  (save-excursion
    (cond ((or (paredit-in-comment-p)
	       (paredit-in-char-p))
	   (error "Invalid context for slurpage"))
	  ((paredit-in-string-p)
	   (paredit-backward-slurp-into-string))
	  (t
	   (paredit-backward-slurp-into-list)))))

(defun paredit-backward-slurp-into-list ()
  (backward-up-list)
  (let ((open (char-after)))
    (delete-char 1)
    (catch 'return
      (while t
	(paredit-handle-sexp-errors
	    (progn (backward-sexp)
		   (throw 'return nil))
	  (backward-up-list))))
    (insert open))
  ;; Reindent the line at the beginning of wherever we inserted the
  ;; opening parenthesis, and then indent the whole S-expression.
  (backward-up-list)
  (lisp-indent-line)
  (indent-sexp))

(defun paredit-backward-slurp-into-string ()
  (goto-char (car (paredit-string-start+end-points)))
  ;; Signal any errors that we might get first, before mucking with the
  ;; buffer's contents.
  (save-excursion (backward-sexp))
  (let ((open (char-after))
	(target (point)))
    (message "open = %S" open)
    (delete-char 1)
    (backward-sexp)
    (insert open)
    (paredit-forward-for-quote target)))

(defun paredit-backward-adopt-sexp ()
  "Add the contents of the S-expression preceding the current list into
  that list by moving the closing delimiter and removing parentheses.
Automatically reindent the whole form into which new S-expression was
  slurped.
If in a string, do a regular slurp instead."
  (interactive)
  (save-excursion
    (cond ((or (paredit-in-comment-p)
	       (paredit-in-char-p))
	   (error "Invalid context for adopting"))
	  ((paredit-in-string-p)
	   (paredit-backward-slurp-into-string))
	  (t
	   (paredit-backward-adopt-into-list)))))

(defun paredit-backward-adopt-into-list ()
  (backward-up-list)
  (paredit-join-sexps)
  ;; Reindent the line at the beginning of wherever we inserted the
  ;; opening parenthesis, and then indent the whole S-expression.
  (backward-up-list)
  (lisp-indent-line)
  (indent-sexp))

(defun paredit-backward-join-sexp ()
  (interactive)
  (save-excursion
    (cond ((or (paredit-in-comment-p)
	       (paredit-in-char-p)
	       (paredit-in-string-p))
	   (error "Invalid context for joining"))
	  (t
	   (save-excursion
	     (backward-up-list)
	     (backward-sexp)
	     (down-list)
	     (paredit-forward-slurp-sexp))))))

(defun paredit-backward-barf-sexp ()
  "Remove the first S-expression in the current list from that list
  by moving the closing delimiter.
Automatically reindent the barfed S-expression and the form from which
  it was barfed."
  (interactive)
  (save-excursion
    (backward-up-list)
    (let ((open (char-after)))
      (delete-char 1)
      (paredit-ignore-sexp-errors
	(paredit-forward-and-indent))
      (while (progn (paredit-skip-whitespace t)
		    (eq (char-after) ?\; ))
	(forward-line 1))
      (if (eobp)
	  (error
	   "Barfing all subexpressions with no close-paren?"))
					;** Don't use `insert' here.  Consider, e.g., barfing from
					;**   (foo|)
					;** and how `save-excursion' works.
      (insert-before-markers open))
    (backward-up-list)
    (lisp-indent-line)
    (indent-sexp)))

(defun paredit-backward-orphan-sexp ()
  "Remove the first S-expression in the current list from that list
  by moving the closing delimiter.
Automatically reindent the barfed S-expression and the form from which
  it was barfed."
  (interactive)
  (save-excursion
    (backward-up-list)
    (forward-char)
    (paredit-forward)
    (paredit-split-sexp)
    (paredit-backward)
    (lisp-indent-line)
    (indent-sexp)))

(defun paredit-backward-leave-sexp ()
  (interactive)
  (save-excursion
    (cond ((or (paredit-in-comment-p)
	       (paredit-in-char-p)
	       (paredit-in-string-p))
	   (error "Invalid context for joining"))
	  (t
	   (save-excursion
	     (backward-up-list)
	     (paredit-backward-barf-sexp))))))

;;;; Splitting & Joining

(defun paredit-split-sexp ()
  "Split the list or string the point is on into two."
  (interactive)
  (cond ((paredit-in-string-p)
	 (insert "\"")
	 (save-excursion (insert " \"")))
	((or (paredit-in-comment-p)
	     (paredit-in-char-p))
	 (error "Invalid context for `paredit-split-sexp'"))
	(t (let ((open  (save-excursion (backward-up-list)
					(char-after)))
		 (close (save-excursion (up-list)
					(char-before))))
	     (delete-horizontal-space)
	     (insert close)
	     (save-excursion (insert ?\ )
			     (insert open)
			     (backward-char)
			     (indent-sexp))))))

(defun paredit-join-sexps ()
  "Join the S-expressions adjacent on either side of the point.
Both must be lists, strings, or atoms; error if there is a mismatch."
  (interactive)
					;++ How ought this to handle comments intervening symbols or strings?
  (save-excursion
    (if (or (paredit-in-comment-p)
	    (paredit-in-string-p)
	    (paredit-in-char-p))
	(error "Invalid context in which to join S-expressions.")
      (let ((left-point  (save-excursion (paredit-point-at-sexp-end)))
	    (right-point (save-excursion
			   (paredit-point-at-sexp-start))))
	(let ((left-char (char-before left-point))
	      (right-char (char-after right-point)))
	  (let ((left-syntax (char-syntax left-char))
		(right-syntax (char-syntax right-char)))
	    (cond ((>= left-point right-point)
		   (error "Can't join a datum with itself."))
		  ((and (eq left-syntax  ?\) )
			(eq right-syntax ?\( )
			(eq left-char (matching-paren right-char))
			(eq right-char (matching-paren left-char)))
		   ;; Leave intermediate formatting alone.
		   (goto-char right-point)
		   (delete-char 1)
		   (goto-char left-point)
		   (backward-delete-char 1)
		   (backward-up-list)
		   (indent-sexp))
		  ((and (eq left-syntax  ?\" )
			(eq right-syntax ?\" ))
		   ;; Delete any intermediate formatting.
		   (delete-region (1- left-point)
				  (1+ right-point)))
		  ((and (memq left-syntax  '(?w ?_)) ; Word or symbol
			(memq right-syntax '(?w ?_)))
		   (delete-region left-point right-point))
		  (t
		   (error "Mismatched S-expressions to join.")))))))))

;;;; Utilities

(defun paredit-in-string-escape-p ()
  "True if the point is on a character escape of a string.
This is true only if the character is preceded by an odd number of
  backslashes.
This assumes that `paredit-in-string-p' has already returned true."
  (let ((oddp nil))
    (save-excursion
      (while (eq (char-before) ?\\ )
	(setq oddp (not oddp))
	(backward-char)))
    oddp))

(defun paredit-in-char-p (&optional arg)
  "True if the point is immediately after a character literal.
A preceding escape character, not preceded by another escape character,
  is considered a character literal prefix.  (This works for elisp,
  Common Lisp, and Scheme.)
Assumes that `paredit-in-string-p' is false, so that it need not handle
  long sequences of preceding backslashes in string escapes.  (This
  assumes some other leading character token -- ? in elisp, # in Scheme
  and Common Lisp.)"
  (let ((arg (or arg (point))))
    (and (eq (char-before arg) ?\\ )
	 (not (eq (char-before (1- arg)) ?\\ )))))

(defun paredit-forward-and-indent ()
  "Move forward an S-expression, indenting it fully.
Indent with `lisp-indent-line' and then `indent-sexp'."
  (forward-sexp)			; Go forward, and then find the
  (save-excursion			;   beginning of this next
    (backward-sexp)			;   S-expression.
    (lisp-indent-line)			; Indent its opening line, and
    (indent-sexp)))			;   the rest of it.

(defun paredit-skip-whitespace (trailing-p &optional limit)
  "Skip past any whitespace, or until the point LIMIT is reached.
If TRAILING-P is nil, skip leading whitespace; otherwise, skip trailing
  whitespace."
  (funcall (if trailing-p 'skip-chars-forward 'skip-chars-backward)
	   " \t\n"	     ; This should skip using the syntax table, but LF
	   limit))		; is a comment end, not newline, in Lisp mode.

(defalias 'paredit-region-active-p
  (xcond ((paredit-xemacs-p) 'region-active-p)
	 ((paredit-gnu-emacs-p)
	  (lambda ()
	    (and mark-active transient-mark-mode)))))

(defun kill-region-new (start end)
  "Kill the region between START and END.
Do not append to any current kill, and
 do not let the next kill append to this one."
  (interactive "r")					      ;Eh, why not?
  ;; KILL-REGION sets THIS-COMMAND to tell the next kill that the last
  ;; command was a kill.  It also checks LAST-COMMAND to see whether it
  ;; should append.  If we bind these locally, any modifications to
  ;; THIS-COMMAND will be masked, and it will not see LAST-COMMAND to
  ;; indicate that it should append.
  (let ((this-command nil)
	(last-command nil))
    (kill-region start end)))

;;;;; S-expression Parsing Utilities

					;++ These routines redundantly traverse S-expressions a great deal.
					;++ If performance issues arise, this whole section will probably have
					;++ to be refactored to preserve the state longer, like paredit.scm
					;++ does, rather than to traverse the definition N times for every key
					;++ stroke as it presently does.

(defun paredit-current-parse-state ()
  "Return parse state of point from beginning of defun."
  (let ((point (point)))
    (beginning-of-defun)
    ;; Calling PARSE-PARTIAL-SEXP will advance the point to its second
    ;; argument (unless parsing stops due to an error, but we assume it
    ;; won't in paredit-mode).
    (parse-partial-sexp (point) point)))

(defun paredit-in-string-p (&optional state)
  "True if the parse state is within a double-quote-delimited string.
If no parse state is supplied, compute one from the beginning of the
  defun to the point."
  ;; 3. non-nil if inside a string (the terminator character, really)
  (and (nth 3 (or state (paredit-current-parse-state)))
       t))

(defun paredit-string-start+end-points (&optional state)
  "Return a cons of the points of open and close quotes of the string.
The string is determined from the parse state STATE, or the parse state
  from the beginning of the defun to the point.
This assumes that `paredit-in-string-p' has already returned true, i.e.
  that the point is already within a string."
  (save-excursion
    ;; 8. character address of start of comment or string; nil if not
    ;;    in one
    (let ((start (nth 8 (or state (paredit-current-parse-state)))))
      (goto-char start)
      (forward-sexp 1)
      (cons start (1- (point))))))

(defun paredit-in-comment-p (&optional state)
  "True if parse state STATE is within a comment.
If no parse state is supplied, compute one from the beginning of the
  defun to the point."
  ;; 4. nil if outside a comment, t if inside a non-nestable comment,
  ;;    else an integer (the current comment nesting)
  (and (nth 4 (or state (paredit-current-parse-state)))
       t))

(defun paredit-point-at-sexp-boundary (n)
  (cond ((< n 0) (paredit-point-at-sexp-start))
	((= n 0) (point))
	((> n 0) (paredit-point-at-sexp-end))))

(defun paredit-point-at-sexp-start ()
  (forward-sexp)
  (backward-sexp)
  (point))

(defun paredit-point-at-sexp-end ()
  (backward-sexp)
  (forward-sexp)
  (point))

(defun paredit-indent-and-complete-symbol (&optional arg)
  (interactive "p")
  (if slime-mode
      (call-interactively 'slime-indent-and-complete-symbol)
    (call-interactively 'lisp-indent-line)
    (unless (or (looking-back "^\\s-*") (bolp))
      (call-interactively 'lisp-complete-symbol))))

(defun paredit-reindent-defun (&optional arg)
  (interactive "P")
  (if (or (paredit-in-comment-p)
	  (paredit-in-string-p))
      (fill-paragraph arg)
    (save-excursion
      (mark-defun)
      (indent-region (point) (mark)))))

;;;; Refactoring

(defun paredit-refactor-let (name &optional arg as-flet-p)
  "Refactor the current sexp into a let variable.
Inserts the definition into an existing let form if one exists at
the desired level.   Mark is left where you were,  so use C-x C-x
if you don't want to edit the definition further."
  (interactive "s`let' variable name: \np")
  (set-mark (point))
  (unless (eq ?\( (char-after))
    (backward-up-list))
  (let* ((start (point))
	 (end (save-excursion
		(forward-sexp)
		(point)))
	 (sexp (prog1
		   (buffer-substring start end)
		 (delete-region start end))))
    (if as-flet-p
	(insert ?\( name ?\))
      (insert name))
    (backward-up-list arg)
    (let (maybe-top)
      (save-excursion
	(while (looking-at (if as-flet-p
			       "(let\\*?"
			     "(flet"))
	  (backward-up-list))
	(if (looking-at (if as-flet-p
			    "(flet"
			  "(let\\*?"))
	    (setq maybe-top (point))))
      (if maybe-top
	  (goto-char maybe-top)))
    (if (looking-at (if as-flet-p
			"(flet"
		      "(let\\*?"))
	(progn
	  (down-list)
	  (forward-sexp 2)
	  (backward-char)
	  (insert "\n(" name " ")
	  (if as-flet-p
	      (insert "()\n"))
	  (save-excursion
	    (insert sexp ")")
	    (backward-up-list)
	    (lisp-indent-line)
	    (indent-sexp)))
      (paredit-wrap-sexp)
      (if as-flet-p
	  (insert "f"))
      (insert "let ((" name " ")
      (if as-flet-p
	  (insert "()\n"))
      (save-excursion
	(insert sexp "))\n")
	(backward-up-list)
	(lisp-indent-line)
	(indent-sexp)))
    (forward-char)))

(defun paredit-refactor-flet (name &optional arg)
  (interactive "s`flet' function name: \np")
  (paredit-refactor-let name arg t))

(defun paredit-convolute-up-sexp (&optional arg)
  (interactive "p")
  (save-excursion
    (let (body-begin body outer-sexp inner-sexp)
      (unless (eq ?\( (char-after))
	(backward-up-list))
      (down-list)
      (forward-sexp (or arg 2))
      (skip-chars-forward " \t\n")
      (setq body-begin (point))
      (backward-up-list)
      (forward-sexp)
      (backward-char)
      (setq body (prog1
		     (buffer-substring body-begin (point))
		   (delete-region body-begin (point))))
      (backward-up-list)
      (setq inner-sexp
	    (let ((end (save-excursion
			 (forward-sexp) (point))))
	      (prog1
		  (buffer-substring (point) end)
		(delete-region (point) end))))
      (backward-up-list)
      (setq outer-sexp
	    (let ((end (save-excursion
			 (forward-sexp) (point))))
	      (prog1
		  (buffer-substring (point) end)
		(delete-region (point) end))))
      (insert inner-sexp)
      (backward-sexp)
      (lisp-indent-line)
      (indent-sexp)
      (forward-sexp)
      (backward-char)
      (insert outer-sexp)
      (backward-sexp)
      (lisp-indent-line)
      (indent-sexp)
      (forward-sexp)
      (backward-char)
      (insert body))))

;;;; Initialization

(paredit-define-keys)
(paredit-annotate-mode-with-examples)
(paredit-annotate-functions-with-examples)

(provide 'paredit)

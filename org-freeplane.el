;;; org-freeplane.el --- Export Org files to freeplane

;; Copyright (C) 2009-2013 Free Software Foundation, Inc.

;; Author: Lennart Borgman (lennart O borgman A gmail O com)
;; Keywords: outlines, hypermedia, calendar, wp
;; Homepage: http://orgmode.org
;;
;; This file is part of GNU Emacs.
;;
;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;; --------------------------------------------------------------------
;; Features that might be required by this library:
;;
;; `backquote', `bytecomp', `cl', `easymenu', `font-lock',
;; `noutline', `org', `org-compat', `org-faces', `org-footnote',
;; `org-list', `org-macs', `org-src', `outline', `syntax',
;; `time-date', `xml'.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Commentary:
;;
;; This file tries to implement some functions useful for
;; transformation between org-mode and Freeplane files.
;;
;; Here are the commands you can use:
;;
;;    M-x `org-freeplane-from-org-mode'
;;    M-x `org-freeplane-from-org-mode-node'
;;    M-x `org-freeplane-from-org-sparse-tree'
;;
;;    M-x `org-freeplane-to-org-mode'
;;
;;    M-x `org-freeplane-show'
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Change log:
;;
;; 2009-02-15: Added check for next level=current+1
;; 2009-02-21: Fixed bug in `org-freeplane-to-org-mode'.
;; 2009-10-25: Added support for `org-odd-levels-only'.
;;             Added y/n question before showing in Freeplane.
;; 2009-11-04: Added support for #+BEGIN_HTML.
;;
;;; Code:

(require 'xml)
(require 'org)
					;(require 'rx)
(require 'org-exp)
(eval-when-compile (require 'cl))

(defgroup org-freeplane nil
  "Customization group for org-freeplane export/import."
  :group 'org)

;; Fix-me: I am not sure these are useful:
;;
;; (defcustom org-freeplane-main-fgcolor "black"
;;   "Color of main node's text."
;;   :type 'color
;;   :group 'org-freeplane)

;; (defcustom org-freeplane-main-color "black"
;;   "Background color of main node."
;;   :type 'color
;;   :group 'org-freeplane)

;; (defcustom org-freeplane-child-fgcolor "black"
;;   "Color of child nodes' text."
;;   :type 'color
;;   :group 'org-freeplane)

;; (defcustom org-freeplane-child-color "black"
;;   "Background color of child nodes."
;;   :type 'color
;;   :group 'org-freeplane)

(defvar org-freeplane-node-style nil "Internal use.")

(defcustom org-freeplane-node-styles nil
  "Styles to apply to node.
NOT READY YET."
  :type '(repeat
          (list :tag "Node styles for file"
                (regexp :tag "File name")
                (repeat
                 (list :tag "Node"
                       (regexp :tag "Node name regexp")
                       (set :tag "Node properties"
                            (list :format "%v" (const :format "" node-style)
                                  (choice :tag "Style"
                                          :value bubble
                                          (const bubble)
                                          (const fork)))
                            (list :format "%v" (const :format "" color)
                                  (color :tag "Color" :value "red"))
                            (list :format "%v" (const :format "" background-color)
                                  (color :tag "Background color" :value "yellow"))
                            (list :format "%v" (const :format "" edge-color)
                                  (color :tag "Edge color" :value "green"))
                            (list :format "%v" (const :format "" edge-style)
                                  (choice :tag "Edge style" :value bezier
                                          (const :tag "Linear" linear)
                                          (const :tag "Bezier" bezier)
                                          (const :tag "Sharp Linear" sharp-linear)
                                          (const :tag "Sharp Bezier" sharp-bezier)))
                            (list :format "%v" (const :format "" edge-width)
                                  (choice :tag "Edge width" :value thin
                                          (const :tag "Parent" parent)
                                          (const :tag "Thin" thin)
                                          (const 1)
                                          (const 2)
                                          (const 4)
                                          (const 8)))
                            (list :format "%v" (const :format "" italic)
                                  (const :tag "Italic font" t))
                            (list :format "%v" (const :format "" bold)
                                  (const :tag "Bold font" t))
                            (list :format "%v" (const :format "" font-name)
                                  (string :tag "Font name" :value "SansSerif"))
                            (list :format "%v" (const :format "" font-size)
                                  (integer :tag "Font size" :value 12)))))))
  :group 'org-freeplane)

;;;###autoload
(defun org-export-as-freeplane (&optional hidden ext-plist
					 to-buffer body-only pub-dir)
  "Export the current buffer as a Freeplane file.
If there is an active region, export only the region.  HIDDEN is
obsolete and does nothing.  EXT-PLIST is a property list with
external parameters overriding org-mode's default settings, but
still inferior to file-local settings.  When TO-BUFFER is
non-nil, create a buffer with that name and export to that
buffer.  If TO-BUFFER is the symbol `string', don't leave any
buffer behind but just return the resulting HTML as a string.
When BODY-ONLY is set, don't produce the file header and footer,
simply return the content of the document (all top level
sections).  When PUB-DIR is set, use this as the publishing
directory.

See `org-freeplane-from-org-mode' for more information."
  (interactive "P")
  (let* ((opt-plist (org-combine-plists (org-default-export-plist)
					ext-plist
					(org-infile-export-plist)))
	 (region-p (org-region-active-p))
	 (rbeg (and region-p (region-beginning)))
	 (rend (and region-p (region-end)))
	 (subtree-p
	  (if (plist-get opt-plist :ignore-subtree-p)
	      nil
	    (when region-p
	      (save-excursion
		(goto-char rbeg)
		(and (org-at-heading-p)
		     (>= (org-end-of-subtree t t) rend))))))
	 (opt-plist (setq org-export-opt-plist
			  (if subtree-p
			      (org-export-add-subtree-options opt-plist rbeg)
			    opt-plist)))
	 (bfname (buffer-file-name (or (buffer-base-buffer) (current-buffer))))
	 (filename (concat (file-name-as-directory
			    (or pub-dir
				(org-export-directory :ascii opt-plist)))
			   (file-name-sans-extension
			    (or (and subtree-p
				     (org-entry-get (region-beginning)
						    "EXPORT_FILE_NAME" t))
				(file-name-nondirectory bfname)))
			   ".mm")))
    (when (file-exists-p filename)
      (delete-file filename))
    (cond
     (subtree-p
      (org-freeplane-from-org-mode-node (line-number-at-pos rbeg)
				       filename))
     (t (org-freeplane-from-org-mode bfname filename)))))

;;;###autoload
(defun org-freeplane-show (mm-file)
  "Show file MM-FILE in Freeplane."
  (interactive
   (list
    (save-match-data
      (let ((name (read-file-name "Freeplane file: "
                                  nil nil nil
                                  (if (buffer-file-name)
                                      (let* ((name-ext (file-name-nondirectory (buffer-file-name)))
                                             (name (file-name-sans-extension name-ext))
                                             (ext (file-name-extension name-ext)))
                                        (cond
                                         ((string= "mm" ext)
                                          name-ext)
                                         ((string= "org" ext)
                                          (let ((name-mm (concat name ".mm")))
                                            (if (file-exists-p name-mm)
                                                name-mm
                                              (message "Not exported to Freeplane format yet")
                                              "")))
                                         (t
                                          "")))
                                    "")
                                  ;; Fix-me: Is this an Emacs bug?
                                  ;; This predicate function is never
                                  ;; called.
                                  (lambda (fn)
                                    (string-match "^mm$" (file-name-extension fn))))))
        (setq name (expand-file-name name))
        name))))
  (org-open-file mm-file))

(defconst org-freeplane-org-nfix "--org-mode: ")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Format converters

(defun org-freeplane-escape-str-from-org (org-str)
  "Do some html-escaping of ORG-STR and return the result.
The characters \"&<> will be escaped."
  (let ((chars (append org-str nil))
        (fm-str ""))
    (dolist (cc chars)
      (setq fm-str
            (concat fm-str
                    (if (< cc 160)
                        (cond
                         ((= cc ?\") "&quot;")
                         ((= cc ?\&) "&amp;")
                         ((= cc ?\<) "&lt;")
                         ((= cc ?\>) "&gt;")
                         (t (char-to-string cc)))
                      ;; Formatting as &#number; is maybe needed
                      ;; according to a bug report from kazuo
                      ;; fujimoto, but I have now instead added a xml
                      ;; processing instruction saying that the mm
                      ;; file is utf-8:
                      ;;
                      ;; (format "&#x%x;" (- cc ;; ?\x800))
		      (format "&#x%x;" (encode-char cc 'ucs))
                      ))))
    fm-str))

;;(org-freeplane-unescape-str-to-org "&#x6d;A&#x224C;B&lt;C&#x3C;&#x3D;")
;;(org-freeplane-unescape-str-to-org "&#x3C;&lt;")
(defun org-freeplane-unescape-str-to-org (fm-str)
  "Do some html-unescaping of FM-STR and return the result.
This is the opposite of `org-freeplane-escape-str-from-org' but it
will also unescape &#nn;."
  (let ((org-str fm-str))
    (setq org-str (replace-regexp-in-string "&quot;" "\"" org-str))
    (setq org-str (replace-regexp-in-string "&amp;" "&" org-str))
    (setq org-str (replace-regexp-in-string "&lt;" "<" org-str))
    (setq org-str (replace-regexp-in-string "&gt;" ">" org-str))
    (setq org-str (replace-regexp-in-string
		   "&#x\\([a-f0-9]\\{2,4\\}\\);"
		   (lambda (m)
		     (char-to-string
		      (+ (string-to-number (match-string 1 m) 16)
			 0 ;?\x800 ;; What is this for? Encoding?
			 )))
		   org-str))))

;; (let* ((str1 "a quote: \", an amp: &, lt: <; over 256: ������")
;;        (str2 (org-freeplane-escape-str-from-org str1))
;;        (str3 (org-freeplane-unescape-str-to-org str2)))
;;     (unless (string= str1 str3)
;;       (error "Error str3=%s" str3)))

(defun org-freeplane-convert-links-helper (matched)
  "Helper for `org-freeplane-convert-links-from-org'.
MATCHED is the link just matched."
  (let* ((link (match-string 1 matched))
         (text (match-string 2 matched))
         (ext (file-name-extension link))
         (col-pos (org-string-match-p ":" link))
         (is-img (and (image-type-from-file-name link)
                      (let ((url-type (substring link 0 col-pos)))
                        (member url-type '("file" "http" "https")))))
	 )
    (if is-img
        ;; Fix-me: I can't find a way to get the border to "shrink
        ;; wrap" around the image using <div>.
        ;;
        ;; (concat "<div style=\"border: solid 1px #ddd; width:auto;\">"
        ;;         "<img src=\"" link "\" alt=\"" text "\" />"
        ;;         "<br />"
        ;;         "<i>" text "</i>"
        ;;         "</div>")
        (concat "<table border=\"0\" style=\"border: solid 1px #ddd;\"><tr><td>"
                "<img src=\"" link "\" alt=\"" text "\" />"
                "<br />"
                "<i>" text "</i>"
                "</td></tr></table>")
      (concat "<a href=\"" link "\">" text "</a>"))))

(defun org-freeplane-convert-links-from-org (org-str)
  "Convert org links in ORG-STR to freeplane links and return the result."
  (let ((fm-str (replace-regexp-in-string
                 ;;(rx (not (any "[\""))
                 ;;    (submatch
                 ;;     "http"
                 ;;     (opt ?\s)
                 ;;     "://"
                 ;;     (1+
                 ;;      (any "-%.?@a-zA-Z0-9()_/:~=&#"))))
		 "[^\"[]\\(http ?://[--:#%&()=?-Z_a-z~]+\\)"
                 "[[\\1][\\1]]"
                 org-str
                 nil ;; fixedcase
                 nil ;; literal
                 1   ;; subexp
                 )))
    (replace-regexp-in-string
     ;;(rx "[["
     ;;	 (submatch (*? nonl))
     ;; "]["
     ;; (submatch (*? nonl))
     ;; "]]")
     "\\[\\[\\(.*?\\)]\\[\\(.*?\\)]]"
     ;;"<a href=\"\\1\">\\2</a>"
     'org-freeplane-convert-links-helper
     fm-str t t)))

;;(org-freeplane-convert-links-to-org "<a href=\"http://www.somewhere/\">link-text</a>")
(defun org-freeplane-convert-links-to-org (fm-str)
  "Convert freeplane links in FM-STR to org links and return the result."
  (let ((org-str (replace-regexp-in-string
                  ;;(rx "<a"
                  ;;    space
                  ;;    (0+
                  ;;     (0+ (not (any ">")))
                  ;;     space)
                  ;;    "href=\""
                  ;;    (submatch (0+ (not (any "\""))))
                  ;;    "\""
                  ;;    (0+ (not (any ">")))
                  ;;     ">"
                  ;;     (submatch (0+ (not (any "<"))))
                  ;;     "</a>")
		  "<a[[:space:]]\\(?:[^>]*[[:space:]]\\)*href=\"\\([^\"]*\\)\"[^>]*>\\([^<]*\\)</a>"
                  "[[\\1][\\2]]"
                  fm-str)))
    org-str))

;; Fix-me:
;;(defun org-freeplane-convert-drawers-from-org (text)
;;  )

;;   (let* ((str1 "[[http://www.somewhere/][link-text]")
;;          (str2 (org-freeplane-convert-links-from-org str1))
;;        (str3 (org-freeplane-convert-links-to-org str2)))
;;     (unless (string= str1 str3)
;;     (error "Error str3=%s" str3)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Org => Freeplane

(defvar org-freeplane-bol-helper-base-indent nil)

(defun org-freeplane-bol-helper (matched)
  "Helper for `org-freeplane-convert-text-p'.
MATCHED is the link just matched."
  (let ((res "")
        (bi org-freeplane-bol-helper-base-indent))
    (dolist (cc (append matched nil))
      (if (= 32 cc)
          ;;(setq res (concat res "&nbsp;"))
          ;; We need to use the numerical version.  Otherwise Freeplane
          ;; ver 0.9.0 RC9 can not export to html/javascript.
          (progn
            (if (< 0 bi)
                (setq bi (1- bi))
              (setq res (concat res "&#160;"))))
        (setq res (concat res (char-to-string cc)))))
    res))
;; (setq x (replace-regexp-in-string "\n +" 'org-freeplane-bol-nbsp-helper "\n  "))

(defun org-freeplane-convert-text-p (text)
  "Convert TEXT to html with <p> paragraphs."
  ;; (string-match-p "[^ ]" "  a")
  (setq org-freeplane-bol-helper-base-indent (org-string-match-p "[^ ]" text))
  (setq text (org-freeplane-escape-str-from-org text))

  (setq text (replace-regexp-in-string "\\([[:space:]]\\)\\(/\\)\\([^/]+\\)\\(/\\)\\([[:space:]]\\)" "\\1<i>\\3</i>\\5" text))
  (setq text (replace-regexp-in-string "\\([[:space:]]\\)\\(\*\\)\\([^*]+\\)\\(\*\\)\\([[:space:]]\\)" "\\1<b>\\3</b>\\5" text))

  (setq text (concat "<p>" text))
  (setq text (replace-regexp-in-string "\n[[:blank:]]*\n" "</p><p>" text))
  (setq text (replace-regexp-in-string "\\(?:<p>\\|\n\\) +" 'org-freeplane-bol-helper text))
  (setq text (replace-regexp-in-string "\n" "<br />" text))
  (setq text (concat text "</p>"))

  (org-freeplane-convert-links-from-org text))

(defcustom org-freeplane-node-css-style
  "p { margin-top: 3px; margin-bottom: 3px; }"
  "CSS style for Freeplane nodes."
  ;; Fix-me: I do not understand this.  It worked to export from Freeplane
  ;; with this setting now, but not before??? Was this perhaps a java
  ;; bug or is it a windows xp bug (some resource gets exhausted if you
  ;; use sticky keys which I do).
  :version "24.1"
  :group 'org-freeplane)

(defun org-freeplane-org-text-to-freeplane-subnode/note (node-name start end drawers-regexp)
  "Convert text part of org node to freeplane subnode or note.
Convert the text part of the org node named NODE-NAME. The text
is in the current buffer between START and END. Drawers matching
DRAWERS-REGEXP are converted to freeplane notes."
  ;; fix-me: doc
  (let ((text (buffer-substring-no-properties start end))
        (node-res "")
        (note-res ""))
    (save-match-data
      ;;(setq text (org-freeplane-escape-str-from-org text))
      ;; First see if there is something that should be moved to the
      ;; note part:
      (let (drawers)
        (while (string-match drawers-regexp text)
          (setq drawers (cons (match-string 0 text) drawers))
          (setq text
                (concat (substring text 0 (match-beginning 0))
                        (substring text (match-end 0))))
          )
        (when drawers
          (dolist (drawer drawers)
            (let ((lines (split-string drawer "\n")))
              (dolist (line lines)
                (setq note-res (concat
                                note-res
                                org-freeplane-org-nfix line "<br />\n")))
              ))))

      (when (> (length note-res) 0)
        (setq note-res (concat
                        "<richcontent TYPE=\"NOTE\"><html>\n"
                        "<head>\n"
                        "</head>\n"
                        "<body>\n"
                        note-res
                        "</body>\n"
                        "</html>\n"
                        "</richcontent>\n")))

      ;; There is always an LF char:
      (when (> (length text) 1)
        (setq node-res (concat
                        "<node style=\"bubble\" background_color=\"#eeee00\">\n"
                        "<richcontent TYPE=\"NODE\"><html>\n"
                        "<head>\n"
                        (if (= 0 (length org-freeplane-node-css-style))
                            ""
                          (concat
			   "<style type=\"text/css\">\n"
			   "<!--\n"
                           org-freeplane-node-css-style
			   "-->\n"
                           "</style>\n"))
                        "</head>\n"
                        "<body>\n"))
        (let ((begin-html-mark (regexp-quote "#+BEGIN_HTML"))
              (end-html-mark   (regexp-quote "#+END_HTML"))
              head
              end-pos
              end-pos-match
              )
          ;; Take care of #+BEGIN_HTML - #+END_HTML
          (while (string-match begin-html-mark text)
            (setq head (substring text 0 (match-beginning 0)))
            (setq end-pos-match (match-end 0))
            (setq node-res (concat node-res
                                   (org-freeplane-convert-text-p head)))
            (setq text (substring text end-pos-match))
            (setq end-pos (string-match end-html-mark text))
            (if end-pos
                (setq end-pos-match (match-end 0))
              (message "org-freeplane: Missing #+END_HTML")
              (setq end-pos (length text))
              (setq end-pos-match end-pos))
            (setq node-res (concat node-res
                                   (substring text 0 end-pos)))
            (setq text (substring text end-pos-match)))
          (setq node-res (concat node-res
                                 (org-freeplane-convert-text-p text))))
        (setq node-res (concat
                        node-res
                        "</body>\n"
                        "</html>\n"
                        "</richcontent>\n"
                        ;; Put a note that this is for the parent node
                        ;; "<richcontent TYPE=\"NOTE\"><html>"
                        ;; "<head>"
                        ;; "</head>"
                        ;; "<body>"
                        ;; "<p>"
                        ;; "-- This is more about \"" node-name "\" --"
                        ;; "</p>"
                        ;; "</body>"
                        ;; "</html>"
                        ;; "</richcontent>\n"
                        note-res
                        "</node>\n" ;; ok
                        )))
      (list node-res note-res))))

(defun org-freeplane-write-node (mm-buffer drawers-regexp
                                          num-left-nodes base-level
                                          current-level next-level this-m2
                                          this-node-end
                                          this-children-visible
                                          next-node-start
                                          next-has-some-visible-child)
  (let* (this-icons
         this-bg-color
         this-m2-link
         this-m2-escaped
         this-rich-node
         this-rich-note
         )
    (when (string-match "TODO" this-m2)
      (setq this-m2 (replace-match "" nil nil this-m2))
      (add-to-list 'this-icons "unchecked")
      (setq this-bg-color "#ffff88")

      ;; handle priorities, e.g. * TODO [#A] foo
      (when (string-match "\\[#\\(.\\)\\]" this-m2)
        (let ((prior (string-to-char (match-string 1 this-m2))))
          (setq this-m2 (replace-match "" nil nil this-m2))
          (cond
           ((= prior ?A)
            (add-to-list 'this-icons "full-1")
            (setq this-bg-color "#ff0000"))
           ((= prior ?B)
            (add-to-list 'this-icons "full-2")
            (setq this-bg-color "#ffaa00"))
           ((= prior ?C)
            (add-to-list 'this-icons "full-3")
            (setq this-bg-color "#ffdd00"))
           ((= prior ?D)
            (add-to-list 'this-icons "full-4")
            (setq this-bg-color "#ffff00"))
           ((= prior ?E)
            (add-to-list 'this-icons "full-5"))
           ((= prior ?F)
            (add-to-list 'this-icons "full-6"))
           ((= prior ?G)
            (add-to-list 'this-icons "full-7"))
           ))))

    (when (string-match "DONE" this-m2)
      (setq this-m2 (replace-match "" nil nil this-m2))
      (add-to-list 'this-icons "checked"))

    (setq this-m2 (org-trim this-m2))
    (when (string-match org-bracket-link-analytic-regexp this-m2)
      (setq this-m2-link (concat "LINK=\"" (match-string 1 this-m2)
                                 (match-string 3 this-m2) "\" ")
            this-m2 (replace-match "\\5" nil nil this-m2 0)))
    (setq this-m2-escaped (org-freeplane-escape-str-from-org this-m2))
    (let ((node-notes (org-freeplane-org-text-to-freeplane-subnode/note
                       this-m2-escaped
                       this-node-end
                       (1- next-node-start)
                       drawers-regexp)))
      (setq this-rich-node (nth 0 node-notes))
      (setq this-rich-note (nth 1 node-notes)))
    (with-current-buffer mm-buffer
      (insert "<node " (if this-m2-link this-m2-link "")
              "TEXT=\"" this-m2-escaped "\"")
      (org-freeplane-get-node-style this-m2)
      (when (> next-level current-level)
        (unless (or this-children-visible
                    next-has-some-visible-child)
          (insert " FOLDED=\"true\"")))
      (when (and (= current-level (1+ base-level))
                 (> num-left-nodes 0))
        (setq num-left-nodes (1- num-left-nodes))
        (insert " POSITION=\"left\""))
      (when this-bg-color
        (insert " BACKGROUND_COLOR=\"" this-bg-color "\""))
      (insert ">\n")
      (when this-icons
        (dolist (icon this-icons)
          (insert "<icon BUILTIN=\"" icon "\"/>\n")))
      )
    (with-current-buffer mm-buffer
      ;;(when this-rich-note (insert this-rich-note))
      (when this-rich-node (insert this-rich-node))))
  num-left-nodes)

(defun org-freeplane-check-overwrite (file interactively)
  "Check if file FILE already exists.
If FILE does not exists return t.

If INTERACTIVELY is non-nil ask if the file should be replaced
and return t/nil if it should/should not be replaced.

Otherwise give an error say the file exists."
  (if (file-exists-p file)
      (if interactively
          (y-or-n-p (format "File %s exists, replace it? " file))
        (error "File %s already exists" file))
    t))

(defvar org-freeplane-node-pattern
  ;;(rx bol
  ;;    (submatch (1+ "*"))
  ;;    (1+ space)
  ;;    (submatch (*? nonl))
  ;;    eol)
  "^\\(\\*+\\)[[:space:]]+\\(.*?\\)$")

(defun org-freeplane-look-for-visible-child (node-level)
  (save-excursion
    (save-match-data
      (let ((found-visible-child nil))
        (while (and (not found-visible-child)
                    (re-search-forward org-freeplane-node-pattern nil t))
          (let* ((m1 (match-string-no-properties 1))
                 (level (length m1)))
            (if (>= node-level level)
                (setq found-visible-child 'none)
              (unless (get-char-property (line-beginning-position) 'invisible)
                (setq found-visible-child 'found)))))
        (eq found-visible-child 'found)
        ))))

(defun org-freeplane-goto-line (line)
  "Go to line number LINE."
  (save-restriction
    (widen)
    (goto-char (point-min))
    (forward-line (1- line))))

(defun org-freeplane-write-mm-buffer (org-buffer mm-buffer node-at-line)
  (with-current-buffer org-buffer
    (dolist (node-style org-freeplane-node-styles)
      (when (org-string-match-p (car node-style) buffer-file-name)
        (setq org-freeplane-node-style (cadr node-style))))
    ;;(message "org-freeplane-node-style =%s" org-freeplane-node-style)
    (save-match-data
      (let* ((drawers (copy-sequence org-drawers))
             drawers-regexp
             (num-top1-nodes 0)
             (num-top2-nodes 0)
             num-left-nodes
             (unclosed-nodes 0)
	     (odd-only org-odd-levels-only)
             (first-time t)
             (current-level 1)
             base-level
             prev-node-end
             rich-text
             unfinished-tag
             node-at-line-level
             node-at-line-last)
        (with-current-buffer mm-buffer
          (erase-buffer)
          (setq buffer-file-coding-system 'utf-8)
          ;; Fix-me: Currently Freeplane (ver 0.9.0 RC9) does not support this:
          ;;(insert "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n")
          (insert "<map version=\"0.9.0\">\n")
          (insert "<!-- To view this file, download free mind mapping software Freeplane or Freeplane from http://freeplane.sourceforge.net/http://freeplane.org -->\n"))
        (save-excursion
          ;; Get special buffer vars:
          (goto-char (point-min))
          (message "Writing Freeplane file...")
          (while (re-search-forward "^#\\+DRAWERS:" nil t)
            (let ((dr-txt (buffer-substring-no-properties (match-end 0) (line-end-position))))
              (setq drawers (append drawers (split-string dr-txt) nil))))
          (setq drawers-regexp
                (concat "^[[:blank:]]*:"
                        (regexp-opt drawers)
                        ;;(rx ":" (0+ blank)
                        ;;    "\n"
                        ;;    (*? anything)
                        ;;    "\n"
                        ;;    (0+ blank)
                        ;;    ":END:"
                        ;;    (0+ blank)
                        ;;    eol)
			":[[:blank:]]*\n\\(?:.\\|\n\\)*?\n[[:blank:]]*:END:[[:blank:]]*$"
			))

          (if node-at-line
              ;; Get number of top nodes and last line for this node
              (progn
                (org-freeplane-goto-line node-at-line)
                (unless (looking-at org-freeplane-node-pattern)
                  (error "No node at line %s" node-at-line))
                (setq node-at-line-level (length (match-string-no-properties 1)))
                (forward-line)
                (setq node-at-line-last
                      (catch 'last-line
                        (while (re-search-forward org-freeplane-node-pattern nil t)
                          (let* ((m1 (match-string-no-properties 1))
                                 (level (length m1)))
                            (if (<= level node-at-line-level)
                                (progn
                                  (beginning-of-line)
                                  (throw 'last-line (1- (point))))
                              (if (= level (1+ node-at-line-level))
                                  (setq num-top2-nodes (1+ num-top2-nodes))))))))
                (setq current-level node-at-line-level)
                (setq num-top1-nodes 1)
                (org-freeplane-goto-line node-at-line))

            ;; First get number of top nodes
            (goto-char (point-min))
            (while (re-search-forward org-freeplane-node-pattern nil t)
              (let* ((m1 (match-string-no-properties 1))
                     (level (length m1)))
                (if (= level 1)
                    (setq num-top1-nodes (1+ num-top1-nodes))
                  (if (= level 2)
                      (setq num-top2-nodes (1+ num-top2-nodes))))))
            ;; If there is more than one top node we need to insert a node
            ;; to keep them together.
            (goto-char (point-min))
            (when (> num-top1-nodes 1)
              (setq num-top2-nodes num-top1-nodes)
              (setq current-level 0)
              (let ((orig-name (if buffer-file-name
                                   (file-name-nondirectory (buffer-file-name))
                                 (buffer-name))))
                (with-current-buffer mm-buffer
                  (insert "<node TEXT=\"" orig-name "\" background_color=\"#00bfff\">\n"
                          ;; Put a note that this is for the parent node
                          "<richcontent TYPE=\"NOTE\"><html>"
                          "<head>"
                          "</head>"
                          "<body>"
                          "<p>"
                          org-freeplane-org-nfix "WHOLE FILE"
                          "</p>"
                          "</body>"
                          "</html>"
                          "</richcontent>\n")))))

          (setq num-left-nodes (floor num-top2-nodes 2))
          (setq base-level current-level)
          (let (this-m2
                this-node-end
                this-children-visible
                next-m2
                next-node-start
                next-level
                next-has-some-visible-child
                next-children-visible
                )
            (while (and
                    (re-search-forward org-freeplane-node-pattern nil t)
                    (if node-at-line-last (<= (point) node-at-line-last) t)
                    )
              (let* ((next-m1 (match-string-no-properties 1))
                     (next-node-end (match-end 0))
                     )
                (setq next-node-start (match-beginning 0))
                (setq next-m2 (match-string-no-properties 2))
                (setq next-level (length next-m1))
                (setq next-children-visible
                      (not (eq 'outline
                               (get-char-property (line-end-position) 'invisible))))
                (setq next-has-some-visible-child
                      (if next-children-visible t
                        (org-freeplane-look-for-visible-child next-level)))
                (when this-m2
                  (setq num-left-nodes (org-freeplane-write-node mm-buffer drawers-regexp num-left-nodes base-level current-level next-level this-m2 this-node-end this-children-visible next-node-start next-has-some-visible-child)))
                (when (if (= num-top1-nodes 1) (> current-level base-level) t)
                  (while (>= current-level next-level)
                    (with-current-buffer mm-buffer
                      (insert "</node>\n")
                      (setq current-level
			    (- current-level (if odd-only 2 1))))))
                (setq this-node-end (1+ next-node-end))
                (setq this-m2 next-m2)
                (setq current-level next-level)
                (setq this-children-visible next-children-visible)
                (forward-char)
                ))
;;;             (unless (if node-at-line-last
;;;                         (>= (point) node-at-line-last)
;;;                       nil)
	    ;; Write last node:
	    (setq this-m2 next-m2)
	    (setq current-level next-level)
	    (setq next-node-start (if node-at-line-last
				      (1+ node-at-line-last)
				    (point-max)))
	    (setq num-left-nodes (org-freeplane-write-node mm-buffer drawers-regexp num-left-nodes base-level current-level next-level this-m2 this-node-end this-children-visible next-node-start next-has-some-visible-child))
	    (with-current-buffer mm-buffer (insert "</node>\n"))
					;)
            )
          (with-current-buffer mm-buffer
            (while (> current-level base-level)
              (insert "</node>\n")
	      (setq current-level
		    (- current-level (if odd-only 2 1)))
              ))
          (with-current-buffer mm-buffer
            (insert "</map>")
            (delete-trailing-whitespace)
            (goto-char (point-min))
            ))))))

(defun org-freeplane-get-node-style (node-name)
  "NOT READY YET."
  ;;<node BACKGROUND_COLOR="#eeee00" CREATED="1234668815593" MODIFIED="1234668815593" STYLE="bubble">
  ;;<font BOLD="true" NAME="SansSerif" SIZE="12"/>
  (let (node-styles
        node-style)
    (dolist (style-list org-freeplane-node-style)
      (let ((node-regexp (car style-list)))
        (message "node-regexp=%s node-name=%s" node-regexp node-name)
        (when (org-string-match-p node-regexp node-name)
          ;;(setq node-style (org-freeplane-do-apply-node-style style-list))
          (setq node-style (cadr style-list))
          (when node-style
            (message "node-style=%s" node-style)
            (setq node-styles (append node-styles node-style)))
          )))))

(defun org-freeplane-do-apply-node-style (style-list)
  (message "style-list=%S" style-list)
  (let ((node-style 'fork)
        (color "red")
        (background-color "yellow")
        (edge-color "green")
        (edge-style 'bezier)
        (edge-width 'thin)
        (italic t)
        (bold t)
        (font-name "SansSerif")
        (font-size 12))
    (dolist (style (cadr style-list))
      (message "    style=%s" style)
      (let ((what (car style)))
        (cond
         ((eq what 'node-style)
          (setq node-style (cadr style)))
         ((eq what 'color)
          (setq color (cadr style)))
         ((eq what 'background-color)
          (setq background-color (cadr style)))

         ((eq what 'edge-color)
          (setq edge-color (cadr style)))

         ((eq what 'edge-style)
          (setq edge-style (cadr style)))

         ((eq what 'edge-width)
          (setq edge-width (cadr style)))

         ((eq what 'italic)
          (setq italic (cadr style)))

         ((eq what 'bold)
          (setq bold (cadr style)))

         ((eq what 'font-name)
          (setq font-name (cadr style)))

         ((eq what 'font-size)
          (setq font-size (cadr style)))
         )
        (insert (format " style=\"%s\"" node-style))
        (insert (format " color=\"%s\"" color))
        (insert (format " background_color=\"%s\"" background-color))
        (insert ">\n")
        (insert "<edge")
        (insert (format " color=\"%s\"" edge-color))
        (insert (format " style=\"%s\"" edge-style))
        (insert (format " width=\"%s\"" edge-width))
        (insert "/>\n")
        (insert "<font")
        (insert (format " italic=\"%s\"" italic))
        (insert (format " bold=\"%s\"" bold))
        (insert (format " name=\"%s\"" font-name))
        (insert (format " size=\"%s\"" font-size))
        ))))

;;;###autoload
(defun org-freeplane-from-org-mode-node (node-line mm-file)
  "Convert node at line NODE-LINE to the Freeplane file MM-FILE.
See `org-freeplane-from-org-mode' for more information."
  (interactive
   (progn
     (unless (org-back-to-heading nil)
       (error "Can't find org-mode node start"))
     (let* ((line (line-number-at-pos))
            (default-mm-file (concat (if buffer-file-name
                                         (file-name-nondirectory buffer-file-name)
                                       "nofile")
                                     "-line-" (number-to-string line)
                                     ".mm"))
            (mm-file (read-file-name "Output Freeplane file: " nil nil nil default-mm-file)))
       (list line mm-file))))
  (when (org-freeplane-check-overwrite mm-file (org-called-interactively-p 'any))
    (let ((org-buffer (current-buffer))
          (mm-buffer (find-file-noselect mm-file)))
      (org-freeplane-write-mm-buffer org-buffer mm-buffer node-line)
      (with-current-buffer mm-buffer
        (basic-save-buffer)
        (when (org-called-interactively-p 'any)
          (switch-to-buffer-other-window mm-buffer)
          (when (y-or-n-p "Show in Freeplane? ")
            (org-freeplane-show buffer-file-name)))))))

;;;###autoload
(defun org-freeplane-from-org-mode (org-file mm-file)
  "Convert the `org-mode' file ORG-FILE to the Freeplane file MM-FILE.
All the nodes will be opened or closed in Freeplane just as you
have them in `org-mode'.

Note that exporting to Freeplane also gives you an alternative way
to export from `org-mode' to html.  You can create a dynamic html
version of the your org file, by first exporting to Freeplane and
then exporting from Freeplane to html.  The 'As
XHTML (JavaScript)' version in Freeplane works very well \(and you
can use a CSS stylesheet to style it)."
  ;; Fix-me: better doc, include recommendations etc.
  (interactive
   (let* ((org-file buffer-file-name)
          (default-mm-file (concat
                            (if org-file
                                (file-name-nondirectory org-file)
                              "nofile")
                            ".mm"))
          (mm-file (read-file-name "Output Freeplane file: " nil nil nil default-mm-file)))
     (list org-file mm-file)))
  (when (org-freeplane-check-overwrite mm-file (org-called-interactively-p 'any))
    (let ((org-buffer (if org-file (find-file-noselect org-file) (current-buffer)))
          (mm-buffer (find-file-noselect mm-file)))
      (org-freeplane-write-mm-buffer org-buffer mm-buffer nil)
      (with-current-buffer mm-buffer
        (basic-save-buffer)
        (when (org-called-interactively-p 'any)
          (switch-to-buffer-other-window mm-buffer)
          (when (y-or-n-p "Show in Freeplane? ")
            (org-freeplane-show buffer-file-name)))))))

;;;###autoload
(defun org-freeplane-from-org-sparse-tree (org-buffer mm-file)
  "Convert visible part of buffer ORG-BUFFER to Freeplane file MM-FILE."
  (interactive
   (let* ((org-file buffer-file-name)
          (default-mm-file (concat
                            (if org-file
                                (file-name-nondirectory org-file)
                              "nofile")
                            "-sparse.mm"))
          (mm-file (read-file-name "Output Freeplane file: " nil nil nil default-mm-file)))
     (list (current-buffer) mm-file)))
  (when (org-freeplane-check-overwrite mm-file (org-called-interactively-p 'any))
    (let (org-buffer
          (mm-buffer (find-file-noselect mm-file)))
      (save-window-excursion
        (org-export-visible ?\  nil)
        (setq org-buffer (current-buffer)))
      (org-freeplane-write-mm-buffer org-buffer mm-buffer nil)
      (with-current-buffer mm-buffer
        (basic-save-buffer)
        (when (org-called-interactively-p 'any)
          (switch-to-buffer-other-window mm-buffer)
          (when (y-or-n-p "Show in Freeplane? ")
            (org-freeplane-show buffer-file-name)))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Freeplane => Org

;; (sort '(b a c) 'org-freeplane-lt-symbols)
(defun org-freeplane-lt-symbols (sym-a sym-b)
  (string< (symbol-name sym-a) (symbol-name sym-b)))
;; (sort '((b . 1) (a . 2) (c . 3)) 'org-freeplane-lt-xml-attrs)
(defun org-freeplane-lt-xml-attrs (attr-a attr-b)
  (string< (symbol-name (car attr-a)) (symbol-name (car attr-b))))

;; xml-parse-region gives things like
;; ((p nil "\n"
;;     (a
;;      ((href . "link"))
;;      "text")
;;     "\n"
;;     (b nil "hej")
;;     "\n"))

;; '(a . nil)

;; (org-freeplane-symbols= 'a (car '(A B)))
(defsubst org-freeplane-symbols= (sym-a sym-b)
  "Return t if downcased names of SYM-A and SYM-B are equal.
SYM-A and SYM-B should be symbols."
  (or (eq sym-a sym-b)
      (string= (downcase (symbol-name sym-a))
               (downcase (symbol-name sym-b)))))

(defun org-freeplane-get-children (parent path)
  "Find children node to PARENT from PATH.
PATH should be a list of steps, where each step has the form

  '(NODE-NAME (ATTR-NAME . ATTR-VALUE))"
  ;; Fix-me: maybe implement op? step: Name, number, attr, attr op val
  ;; Fix-me: case insensitive version for children?
  (let* ((children (if (not (listp (car parent)))
                       (cddr parent)
                     (let (cs)
                       (dolist (p parent)
                         (dolist (c (cddr p))
                           (add-to-list 'cs c)))
                       cs)
                     ))
         (step (car path))
         (step-node (if (listp step) (car step) step))
         (step-attr-list (when (listp step) (sort (cdr step) 'org-freeplane-lt-xml-attrs)))
         (path-tail (cdr path))
         path-children)
    (dolist (child children)
      ;; skip xml.el formatting nodes
      (unless (stringp child)
        ;; compare node name
        (when (if (not step-node)
                  t ;; any node name
                (org-freeplane-symbols= step-node (car child)))
          (if (not step-attr-list)
              ;;(throw 'path-child child) ;; no attr to care about
              (add-to-list 'path-children child)
            (let* ((child-attr-list (cadr child))
                   (step-attr-copy (copy-sequence step-attr-list)))
              (dolist (child-attr child-attr-list)
		;; Compare attr names:
                (when (org-freeplane-symbols= (caar step-attr-copy) (car child-attr))
                  ;; Compare values:
                  (let ((step-val (cdar step-attr-copy))
                        (child-val (cdr child-attr)))
                    (when (if (not step-val)
                              t ;; any value
                            (string= step-val child-val))
                      (setq step-attr-copy (cdr step-attr-copy))))))
              ;; Did we find all?
              (unless step-attr-copy
                ;;(throw 'path-child child)
                (add-to-list 'path-children child)
                ))))))
    (if path-tail
        (org-freeplane-get-children path-children path-tail)
      path-children)))

(defun org-freeplane-get-richcontent-node (node)
  (let ((rc-nodes
         (org-freeplane-get-children node '((richcontent (type . "NODE")) html body))))
    (when (> (length rc-nodes) 1)
      (lwarn t :warning "Unexpected structure: several <richcontent type=\"NODE\" ...>"))
    (car rc-nodes)))

(defun org-freeplane-get-richcontent-note (node)
  (let ((rc-notes
         (org-freeplane-get-children node '((richcontent (type . "NOTE")) html body))))
    (when (> (length rc-notes) 1)
      (lwarn t :warning "Unexpected structure: several <richcontent type=\"NOTE\" ...>"))
    (car rc-notes)))

(defun org-freeplane-test-get-tree-text ()
  (let ((node '(p nil "\n"
		  (a
		   ((href . "link"))
		   "text")
		  "\n"
		  (b nil "hej")
		  "\n")))
    (org-freeplane-get-tree-text node)))
;; (org-freeplane-test-get-tree-text)

(defun org-freeplane-get-tree-text (node)
  (when node
    (let ((ntxt "")
          (link nil)
          (lf-after nil))
      (dolist (n node)
        (case n
          ;;(a (setq is-link t) )
          ((h1 h2 h3 h4 h5 h6 p)
           ;;(setq ntxt (concat "\n" ntxt))
           (setq lf-after 2))
          (br
           (setq lf-after 1))
          (t
           (cond
            ((stringp n)
             (when (string= n "\n") (setq n ""))
             (if link
                 (setq ntxt (concat ntxt
                                    "[[" link "][" n "]]"))
               (setq ntxt (concat ntxt n))))
            ((and n (listp n))
             (if (symbolp (car n))
                 (setq ntxt (concat ntxt (org-freeplane-get-tree-text n)))
               ;; This should be the attributes:
               (dolist (att-val n)
                 (let ((att (car att-val))
                       (val (cdr att-val)))
                   (when (eq att 'href)
                     (setq link val))))))))))
      (if lf-after
          (setq ntxt (concat ntxt (make-string lf-after ?\n)))
        (setq ntxt (concat ntxt " ")))
      ;;(setq ntxt (concat ntxt (format "{%s}" n)))
      ntxt)))

(defun org-freeplane-get-richcontent-node-text (node)
  "Get the node text as from the richcontent node NODE."
  (save-match-data
    (let* ((rc (org-freeplane-get-richcontent-node node))
           (txt (org-freeplane-get-tree-text rc)))
      ;;(when txt (setq txt (replace-regexp-in-string "[[:space:]]+" " " txt)))
      txt
      )))

(defun org-freeplane-get-richcontent-note-text (node)
  "Get the node text as from the richcontent note NODE."
  (save-match-data
    (let* ((rc (org-freeplane-get-richcontent-note node))
           (txt (when rc (org-freeplane-get-tree-text rc))))
      ;;(when txt (setq txt (replace-regexp-in-string "[[:space:]]+" " " txt)))
      txt
      )))

(defun org-freeplane-get-icon-names (node)
  (let* ((icon-nodes (org-freeplane-get-children node '((icon ))))
         names)
    (dolist (icn icon-nodes)
      (setq names (cons (cdr (assq 'builtin (cadr icn))) names)))
    ;; (icon (builtin . "full-1")) ;; TODO:Felix??
    names))

(defun org-freeplane-node-to-org (node level skip-levels)
  (let ((qname (car node))
        (attributes (cadr node))
        text
        ;; Fix-me: note is never inserted
        (note (org-freeplane-get-richcontent-note-text node))
        (mark "-- This is more about ")
        (icons (org-freeplane-get-icon-names node))
        (children (cddr node)))
    (when (< 0 (- level skip-levels))
      (dolist (attrib attributes)
        (case (car attrib)
          ('TEXT (setq text (cdr attrib)))
          ('text (setq text (cdr attrib)))))
      (unless text
        ;; There should be a richcontent node holding the text:
        (setq text (org-freeplane-get-richcontent-node-text node)))
      (when icons
        (when (member "full-1" icons) (setq text (concat "[#A] " text)))
        (when (member "full-2" icons) (setq text (concat "[#B] " text)))
        (when (member "full-3" icons) (setq text (concat "[#C] " text)))
        (when (member "full-4" icons) (setq text (concat "[#D] " text)))
        (when (member "full-5" icons) (setq text (concat "[#E] " text)))
        (when (member "full-6" icons) (setq text (concat "[#F] " text)))
        (when (member "full-7" icons) (setq text (concat "[#G] " text)))
        (when (member "button_cancel" icons) (setq text (concat "TODO " text)))
        )
      (if (and note
               (string= mark (substring note 0 (length mark))))
          (progn
            (setq text (replace-regexp-in-string "\n $" "" text))
            (insert text))
        (case qname
          ('node
           (insert (make-string (- level skip-levels) ?*) " " text "\n")
           (when note
             (insert ":COMMENT:\n" note "\n:END:\n"))
           ))))
    (dolist (child children)
      (unless (or (null child)
                  (stringp child))
        (org-freeplane-node-to-org child (1+ level) skip-levels)))))

;; Fix-me: put back special things, like drawers that are stored in
;; the notes.  Should maybe all notes contents be put in drawers?
;;;###autoload
(defun org-freeplane-to-org-mode (mm-file org-file)
  "Convert Freeplane file MM-FILE to `org-mode' file ORG-FILE."
  (interactive
   (save-match-data
     (let* ((mm-file (buffer-file-name))
            (default-org-file (concat (file-name-nondirectory mm-file) ".org"))
            (org-file (read-file-name "Output org-mode file: " nil nil nil default-org-file)))
       (list mm-file org-file))))
  (when (org-freeplane-check-overwrite org-file (org-called-interactively-p 'any))
    (let ((mm-buffer (find-file-noselect mm-file))
          (org-buffer (find-file-noselect org-file)))
      (with-current-buffer mm-buffer
        (let* ((xml-list (xml-parse-file mm-file))
               (top-node (cadr (cddar xml-list)))
               (note (org-freeplane-get-richcontent-note-text top-node))
               (skip-levels
                (if (and note
                         (string-match "^--org-mode: WHOLE FILE$" note))
                    1
                  0)))
          (with-current-buffer org-buffer
            (erase-buffer)
            (org-freeplane-node-to-org top-node 1 skip-levels)
            (goto-char (point-min))
            (org-set-tags t t) ;; Align all tags
            )
          (switch-to-buffer-other-window org-buffer)
          )))))

(provide 'org-freeplane)

;; Local variables:
;; generated-autoload-file: "org-loaddefs.el"
;; End:

;;; org-freeplane.el ends here

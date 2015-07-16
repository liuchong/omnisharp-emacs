(defun omnisharp-current-type-information (&optional add-to-kill-ring)
  "Display information of the current type under point. With prefix
argument, add the displayed result to the kill ring. This can be used
to insert the result in code, for example."
  (interactive "P")
  (omnisharp-current-type-information-worker 'Type))

(defun omnisharp-current-type-documentation (&optional add-to-kill-ring)
  "Display documentation of the current type under point. With prefix
argument, add the displayed result to the kill ring. This can be used
to insert the result in code, for example."
  (interactive "P")
  (omnisharp-current-type-information-worker 'Documentation))

(defun omnisharp-current-type-information-worker (type-property-name
                                                  &optional add-to-kill-ring)
  "Get type info from the API and display a part of the response as a
message. TYPE-PROPERTY-NAME is a symbol in the type lookup response
from the server side, i.e. 'Type or 'Documentation that will be
displayed to the user."
  (omnisharp-post-message-curl-as-json-async
   (concat (omnisharp-get-host) "typelookup")
   (omnisharp--get-common-params)
   (lambda (response)
     (let ((stuff-to-display (cdr (assoc type-property-name
                                         response))))
       (message stuff-to-display)
       (when add-to-kill-ring
         (kill-new stuff-to-display))))))

(defun omnisharp-current-type-information-to-kill-ring ()
  "Shows the information of the current type and adds it to the kill
ring."
  (interactive)
  (omnisharp-current-type-information t))

(defun omnisharp-find-usages ()
  "Find usages for the symbol under point"
  (interactive)
  (message "Finding usages...")
  (omnisharp--send-command-to-server
   "findusages"
   (omnisharp--get-common-params)
   (-lambda ((&alist 'QuickFixes quickfixes))
     (omnisharp--find-usages-show-response quickfixes))))

(defun omnisharp--find-usages-show-response (quickfixes)
  (if (equal 0 (length quickfixes))
      (message "No usages found.")
    (omnisharp--write-quickfixes-to-compilation-buffer
     quickfixes
     omnisharp--find-usages-buffer-name
     omnisharp-find-usages-header)))

(defun omnisharp-find-implementations-with-ido (&optional other-window)
  (interactive "P")
  (let ((quickfixes (omnisharp--vector-to-list
                     (cdr (assoc 'QuickFixes (omnisharp-post-message-curl-as-json
                                              (concat (omnisharp-get-host) "findimplementations")
                                              (omnisharp--get-common-params)))))))
    (cond ((equal 0 (length quickfixes))
           (message "No implementations found."))
          ((equal 1 (length quickfixes))
           (omnisharp-go-to-file-line-and-column (car quickfixes) other-window))
          (t
           (omnisharp--choose-and-go-to-quickfix-ido
            (mapcar 'omnisharp-format-find-output-to-ido quickfixes)
            other-window)))))

(defun omnisharp-find-usages-with-ido (&optional other-window)
  (interactive "P")
  (let ((quickfixes (omnisharp--vector-to-list
                     (cdr (assoc 'QuickFixes (omnisharp-post-message-curl-as-json
                                              (concat (omnisharp-get-host) "findusages")
                                              (omnisharp--get-common-params)))))))
    (cond ((equal 0 (length quickfixes))
           (message "No usages found."))
          ((equal 1 (length quickfixes))
           (omnisharp-go-to-file-line-and-column (car quickfixes) other-window))
          (t
           (omnisharp--choose-and-go-to-quickfix-ido
            (mapcar 'omnisharp-format-find-output-to-ido quickfixes)
            other-window)))))

(defun omnisharp-find-implementations ()
  "Show a buffer containing all implementations of the interface under
point, or classes derived from the class under point. Allow the user
to select one (or more) to jump to."
  (interactive)
  (message "Finding implementations...")
  (omnisharp-find-implementations-worker
    (omnisharp--get-common-params)
    (lambda (quickfixes)
      (cond ((equal 0 (length quickfixes))
             (message "No implementations found."))

            ;; Go directly to the implementation if there only is one
            ((equal 1 (length quickfixes))
             (omnisharp-go-to-file-line-and-column (car quickfixes)))

            (t
             (omnisharp--write-quickfixes-to-compilation-buffer
              quickfixes
              omnisharp--find-implementations-buffer-name
              omnisharp-find-implementations-header))))))

(defun omnisharp-find-implementations-worker (request callback)
  "Gets a list of QuickFix lisp objects from a findimplementations api call
asynchronously. On completions, CALLBACK is run with the quickfixes as its only argument."
  (declare (indent defun))
  (omnisharp-post-message-curl-as-json-async
   (concat (omnisharp-get-host) "findimplementations")
   request
   (lambda (quickfix-response)
     (apply callback (list (omnisharp--vector-to-list
                            (cdr (assoc 'QuickFixes quickfix-response))))))))

(defun omnisharp-find-implementations-popup ()
  "Show a popup containing all implementations of the interface under
point, or classes derived from the class under point. Allow the user
to select one (or more) to jump to."
  (interactive)
  (message "Finding implementations...")
  (omnisharp-find-implementations-worker
    (omnisharp--get-common-params)
    (lambda (quickfixes)
      (cond ((equal 0 (length quickfixes))
             (message "No implementations found."))

            ;; Go directly to the implementation if there only is one
            ((equal 1 (length quickfixes))
             (omnisharp-go-to-file-line-and-column (car quickfixes)))

            (t
             (omnisharp-navigate-to-implementations-popup quickfixes))))))

(defun omnisharp-get-implementation-title (item)
  "Get the human-readable class-name declaration from an alist with
information about implementations found in omnisharp-find-implementations-popup."
  (let* ((text (cdr (assoc 'Text item))))
    (if (or (string-match-p " class " text)
            (string-match-p " interface " text))
	text
      (concat
       (file-name-nondirectory (cdr (assoc 'FileName item)))
       ":"
       (number-to-string (cdr (assoc 'Line item))))
      )))

(defun omnisharp-get-implementation-by-name (items title)
  "Return the implementation-object which matches the provided title."
  (--first (string= title (omnisharp-get-implementation-title it))
	   items))

(defun omnisharp-navigate-to-implementations-popup (items)
  "Creates a navigate-to-implementation popup with the provided items
and navigates to the selected one."
  (let* ((chosen-title (popup-menu* (mapcar 'omnisharp-get-implementation-title items)))
	 (chosen-item  (omnisharp-get-implementation-by-name items chosen-title)))
    (omnisharp-go-to-file-line-and-column chosen-item)))

(defun omnisharp-rename ()
  "Rename the current symbol to a new name. Lets the user choose what
name to rename to, defaulting to the current name of the symbol."
  (interactive)
  (let* ((current-word (thing-at-point 'symbol))
         (rename-to (read-string "Rename to: " current-word))
         (rename-request
          (->> (omnisharp--get-common-params)
            (cons `(RenameTo . ,rename-to))
            (cons `(WantsTextChanges . true))))

         (modified-file-responses
          (omnisharp-rename-worker rename-request))
         (location-before-rename
          (omnisharp--get-common-params-for-emacs-side-use)))

    (-if-let (error-message (cdr (assoc 'ErrorMessage modified-file-responses)))
        (message error-message)

      (progn
        ;; The server will possibly update some files that are currently open.
        ;; Save all buffers to avoid conflicts / losing changes
        (save-some-buffers t)

        (--each modified-file-responses
          (-let (((&alist 'Changes changes
                          'FileName file-name) it))
            (omnisharp--update-files-with-text-changes
             file-name
             (omnisharp--vector-to-list changes))))

        ;; Keep point in the buffer that initialized the rename so that
        ;; the user does not feel disoriented
        (omnisharp-go-to-file-line-and-column location-before-rename)

        (message "Rename complete in files: \n%s"
                 (-interpose "\n" (--map (cdr (assoc 'FileName it))
                                         modified-file-responses)))))))

(defun omnisharp-rename-worker (rename-request)
  "Given a RenameRequest, returns a list of ModifiedFileResponse
objects."
  (let* ((rename-responses
          (omnisharp-post-message-curl-as-json
           (concat (omnisharp-get-host) "rename")
           rename-request))
         (modified-files (omnisharp--vector-to-list
                          (cdr (assoc 'Changes rename-responses)))))
    modified-files))

(defun omnisharp-rename-interactively ()
  "Rename the current symbol to a new name. Lets the user choose what
name to rename to, defaulting to the current name of the symbol. Any
renames require interactive confirmation from the user."
  (interactive)
  (let* ((current-word (thing-at-point 'symbol))
         (rename-to (read-string "Rename to: " current-word))
         (delimited
          (y-or-n-p "Only rename full words?"))
         (all-solution-files
          (omnisharp--get-solution-files-list-of-strings))
         (location-before-rename
          (omnisharp--get-common-params-for-emacs-side-use)))

    (setq omnisharp--current-solution-files all-solution-files)
    (tags-query-replace current-word
                        rename-to
                        delimited
                        ;; This is expected to be a form that will be
                        ;; evaluated to get the list of all files to
                        ;; process.
                        'omnisharp--current-solution-files)
    ;; Keep point in the buffer that initialized the rename so that
    ;; the user deos not feel disoriented
    (omnisharp-go-to-file-line-and-column location-before-rename)))


(provide 'omnisharp-current-symbol-actions)

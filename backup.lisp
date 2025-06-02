#!/usr/bin/env -S guix shell sbcl rsync -- sbcl --script

(require "uiop")

(defparameter *backup-location* #P"/var/packup/")

(defparameter *keep-version-count* 12)

(defun ensure-namestring (pathname-or-string)
  (etypecase pathname-or-string
    (string pathname-or-string)
    (pathname (uiop:native-namestring pathname-or-string))))

(defun sync (from to &key base)
  "Uses rsync to sync remotely or locally"
  (let ((command (list "rsync"
                       "-a"
                       "--delete"
                       "--mkpath"
                       "--quiet"
                       "--inplace"
                       "--backup")))
    (when base
        (setf command (append command
                              (list
                               (format nil "--link-dest=~a" (ensure-namestring base))))))
    (let ((from (if (listp from)
                    (mapcar #'ensure-namestring from)
                    (list (ensure-namestring from))))
          (to (ensure-namestring to)))
      (setf command (append command
                            from
                            (list to))))
    (format t "~{~a ~}~%" command)
    (multiple-value-bind (output error-output exit-code)
        (uiop:run-program command)
      (declare (ignore output error-output))
      (unless (= exit-code 0)
        (error "Unsuccessfull sync")))))

(defun directory-contents (directory)
  (append (uiop:directory-files directory)
          (uiop:subdirectories directory)))

(defun basename (path)
  (or (pathname-name path)
      (first (last (pathname-directory path)))))

(defun basedir (path)
  (if (pathname-name path)
      (make-pathname :directory (pathname-directory path))
      (make-pathname :directory (butlast (pathname-directory path)))))

(defun string-until-separator (string separator)
 (subseq string 0 (search separator string)))

(defun string-after-separator (string separator)
  (subseq string (+ (search separator string) (length separator))))

(defun backup-find-previous (path)
  (sort
   (loop for entry in (directory-contents (basedir path))
         when (string= 
               (string-until-separator
                (basename path)
                *backup-version-separator*) 
               (string-until-separator
                (basename entry)
                *backup-version-separator*))
         collect entry)
   (lambda (entry1 entry2)
     (< (parse-integer (string-after-separator (basename entry1) *backup-version-separator*))
        (parse-integer (string-after-separator (basename entry2) *backup-version-separator*))))))

(defun pathname-with-new-name (pathname new-name) 
  (if (pathname-name pathname)
      (make-pathname :defaults pathname
                     :name new-name)
      (make-pathname :defaults pathname
                     :directory (append (butlast (pathname-directory pathname))
                                        (list new-name)))))

(defun backups-update-version (backups)
  (loop for backup in backups
        for version from 1
        for temporary-path = (pathname-with-new-name backup
                                                     (format nil "~a.temp" version))
        collect temporary-path into temporary-paths
        do (rename-file backup
                        temporary-path)
        finally (loop for temporary-path in temporary-paths
                      do (rename-file temporary-path
                                      (pathname-with-new-name temporary-path
                                                              (let ((basename (basename temporary-path)))
                                                                (subseq basename
                                                                        0
                                                                        (- (length basename) (length ".temp")))))))))

(defun delete-file-or-directory (path)
  (if (pathname-name path)
      (delete-file path)
      (delete-directory path :recursive t)))

(defun backups-delete-excess (backups)
  (when (> (length backups) *keep-version-count*)
    (mapcar #'delete-file-or-directory
            (subseq backups *keep-version-count*))))
   
(defun backup-path (path)
  (merge-pathnames path
                   *backup-location*))

(defun device-backup-path (&optional (path #P""))
  (merge-pathnames path
                   (backup-path
                    (make-pathname
                     :directory (list :relative "devices")))))

(defun host-backup-path (&optional (path #P""))
  (merge-pathnames path
                   (device-backup-path (make-pathname :directory (list :relative (uiop:hostname))))))

(defun synced-backup-path (&optional (path #P""))
  (merge-pathnames path
                   (backup-path
                    (make-pathname
                     :directory (list :relative "synced")))))

(defun backup-previous-versions (backup-path)
  (sort
   (uiop:subdirectories (basedir backup-path))
   (lambda (path1 path2)
     (< (parse-integer (basename path1))
        (parse-integer (basename path2))))))

(deftype scope ()
  '(member :device :synced))

(defun host-path-namestring (host path)
  (format nil "~a:~a" host path))

(declaim (ftype (function (list &optional scope) t) backup))
(defun backup (paths &optional (scope :device))
  "Backs up path using incremental backup"
  (declare (type scope scope)
           (type list paths))
  (let* ((backup-name #P"0/")
         (base-path (case scope
                      (:device (host-backup-path #P"1/"))
                      (:synced (synced-backup-path #P"1/"))))
         (backup-path (case scope
                        (:device (host-backup-path backup-name))
                        (:synced (synced-backup-path backup-name)))))
    (sync paths backup-path :base base-path)
    (backups-update-version (backup-previous-versions backup-path))
    (backups-delete-excess (backup-previous-versions backup-path))))

(defun fetch-device-backups (devices)
  (dolist (device devices)
    (destructuring-bind (hostname . url)
        (if (consp device)
            device
            (cons device device))
      (unless (string= hostname (uiop:hostname))
        (let ((base-path (device-backup-path (make-pathname
                                              :directory (list :relative hostname "1"))))
              (backup-path (device-backup-path (make-pathname
                                                :directory (list :relative hostname "0")))))
          (sync
           (host-path-namestring url
                                 base-path)
           backup-path
           :base base-path)
          (backups-update-version (backup-previous-versions backup-path))
          (backups-delete-excess (backup-previous-versions backup-path)))))))

(defun eval-file (file)
  (eval `(progn ,@(uiop:read-file-forms file))))

(defun config-backup (config)
  (destructuring-bind (&key devices device-files synced-files backup-location version-count) config
    (let ((*backup-location* (or backup-location *backup-location*))
          (*keep-version-count* (or version-count *keep-version-count*)))
      (backup synced-files :synced)
      (backup device-files :device)
      (fetch-device-backups devices))))

(defun main ()
  (labels ((config-file (name)
           (merge-pathnames (uiop:xdg-config-pathname)
             (make-pathname :directory (list :relative "packup")
                            :name name))))
    (let ((config (cond 
                    ((uiop:command-line-arguments) (let ((config-file (parse-native-namestring (first (uiop:command-line-arguments)))))
                                                     (if (probe-file config-file)
                                                         (cond 
                                                           ((string= (pathname-type config-file) "sexp") (uiop:read-file-form config-file))
                                                           ((string= (pathname-type config-file) "lisp") (eval-file config-file)))
                                                         (progn
                                                           (format t "ERROR: File not found: ~a~%" config-file)
                                                           (exit :code 1)))))
                   ((probe-file (config-file "config.lisp")) (eval-file (config-file "config.lisp")))
                   ((probe-file (config-file "config.sexp")) (uiop:read-file-form (config-file "config.sexp"))))))
      (config-backup config))))

(main)
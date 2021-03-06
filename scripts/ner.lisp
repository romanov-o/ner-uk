(in-package :cl-user)

(eval-when (:load-toplevel :compile-toplevel :execute)
  (ql:quickload :rutilsx)
  (ql:quickload :yason)
  (ql:quickload :cl-nlp)
  (use-package :rutilsx)
  (use-package :ncore)
  (use-package :nutil)
  (use-package :nlearn)
  (use-package :ntag))

(named-readtables:in-readtable rutilsx:rutilsx-readtable)


(defstruct (entity (:include token)
                   (:print-object
                    (lambda (entity stream)
                      (with-slots (id word pos beg end pos ner) entity
                        (format stream "<~A ~A~@[/~A~]~@[:~A~]~@[ ~A~]>"
                                ner word pos id
                                (when beg
                                  (if end
                                      (fmt "~A..~A" beg end)
                                      beg)))))))
  "Common TOKEN enriched with ner data."
  (ner :рег))


;;; data

(with ((dev-test (split #\Newline (read-file "../doc/dev-test-split.txt")
                        :remove-empty-subseqs t)))
  (defparameter *dev-data*
    (sub dev-test (1+ (position "DEV" dev-test :test 'string=))
         (position "TEST" dev-test :test 'string=)))
  (defparameter *test-data*
    (sub dev-test (1+ (position "TEST" dev-test :test 'string=)))))

(defun make-sent (str)
  (apply 'mapcar ^(make-entity :word % :beg (lt %%) :end (rt %%))
         (multiple-value-list (tokenize <word-chunker> str))))

(defun get-raw-data (only-files &optional gold)
  (let (rez)
    (dolist (file (directory (strcat "../data/*.ann")))
      (when (or (null only-files)
                (member (pathname-name file) only-files :test 'string=))
        (with ((anns (split #\Newline (read-file file) :remove-empty-subseqs t))
               (ann (split-if 'white-char-p (first anns)))
               (anns (rest anns))
               (off 0))
          (dolines (sent (fmt "~A.txt" (substr (princ-to-string file) 0 -4)))
            (let ((toks (make-sent sent)))
              (loop :while (and ann
                                (< (- (parse-integer (? ann 2)) off)
                                   (length sent)))
                    :do
                (with (((_ ent beg end &rest ign) ann))
                  (:= beg (- (parse-integer beg) off)
                      end (- (parse-integer end) off))
                  (when (or (null gold)
                            (eql gold (mkeyw ent)))
                    (dolist (tok toks)
                      (cond ((and (= @tok.beg beg)
                                  (= @tok.end end))
                             (:= @tok.ner (mkeyw ent)))
                            ((= @tok.beg beg)
                             (:= @tok.ner (mkeyw ent)));(strcat ent "-"))))
                            ((= @tok.end end)
                             (:= @tok.ner (mkeyw ent)));(strcat "-" ent))))
                            ((< beg @tok.beg end)
                             (:= @tok.ner (mkeyw ent))))));(strcat "-" ent "-")))))))
                  (:= ann (split-if 'white-char-p (first anns))
                      anns (rest anns))))
              (when toks
                (push (make 'sentence :tokens toks) rez)))
            (:+ off (1+ (length sent)))))))
    rez))


;;; training and testing

(defun train-ner (model-class data &optional (epochs 10))
  (train (make model-class)
         (keep-if ^(notevery ^(eql :рег %) (mapcar 'entity-ner @%.tokens))
                  data)
         :verbose t :epochs epochs))

(defun test-ner (ners dir gold-dir)
  (ensure-directories-exist dir)
  (dolist (file *test-data*)
    (with-out-file (out (fmt "../data/~A.ann" file))
      (let ((off 0) (i 0))
        (dolines (line (fmt "~A~A.txt" gold-dir file))
          (let ((sent (make 'sentence :tokens (make-sent line))))
            (dolist (ner (mklist ners))
              (tag ner sent))
            (dolist (entity (sent-tokens sent))
              (unless (eql :рег @entity.ner)
                (format out "T~A~C~A ~A ~A~C~A~%"
                        (incf i) #\Tab (string-trim "-" @entity.ner)
                        (+ off @entity.beg) (+ off @entity.end)
                        #\Tab @entity.word))))
          (:+ off (1+ (length line))))))))


;;; dict

(defparameter *dict* (load-dict "../../dict-uk/dict-uk.txt"))

(defun load-dict (file)
  (let ((dict #h(equalp))
        (c 0))
    (dolines (line file)
      (with (((word pos) (split #\Space line :remove-empty-subseqs t)))
        (:= pos (slice pos 0 (position #\: pos)))
        (if-it (get# word dict)
               (unless (string= it pos)
                 (:+ c))
               (set# word dict pos))))
    (print c)
    dict))

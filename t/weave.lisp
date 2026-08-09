(in-package #:redis-kit/test)

(describe "cl-weave execution journals"
  (it "derives facts from an execution journal with logic-program"
    (let* ((frames
             (cl-weave:with-execution-journal
               (cl-weave:journal-note :phase :ready)
               (expect 1 :to-be 1)
               (cl-weave:journal-note :phase :done)))
           (program
             (append
              (cl-weave:journal-facts frames)
              (cl-weave:logic-program
                (:- (:phase-note ?index)
                    (:kind ?index :note)
                    (:actual ?index :ready))))))
      (expect (cl-weave:journal-where program (:phase-note ?index))
              :to-equal
              '(((?index . 0))))))
)

  (it "queries journal frames directly with logic-run"
    (let ((frames
            (cl-weave:with-execution-journal
              (cl-weave:journal-note :phase :ready))))
      (expect (cl-weave:journal-where frames
                                      (:kind ?index :note)
                                      (:actual ?index :ready))
              :to-equal
              '(((?index . 0))))
      (expect (cl-weave:logic-run (cl-weave:journal-facts frames)
                                  (:form ?index :phase))
              :to-equal
              '(((?index . 0))))))

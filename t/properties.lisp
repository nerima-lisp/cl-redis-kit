; paredit:ignore-file leftover-inspect-call -- CL-WEAVE's DESCRIBE is the BDD test DSL, not a debugger inspection call.
(in-package #:redis-kit/test)

(describe
    "generative RESP contracts"
  (it-property "round-trips binary-safe command values"
      ((key (gen-string :min-length 0
                        :max-length 12
                        :alphabet "ab01"))
       (value (gen-string :min-length 0
                          :max-length 12
                          :alphabet "xy09")))
    (let ((frame (redis-kit:encode-command "SET" key value)))
      (multiple-value-bind (reply next)
          (redis-kit:decode-reply frame)
        (expect (redis-kit:redis-reply-type reply) :to-be :array)
        (expect (redis-kit:reply-value reply)
                :to-equal
                (list "SET" key value))
        (expect next :to-be (length frame)))))

  (it-property "normalizes numeric values at the wire boundary"
      ((amount (gen-integer :min -1000 :max 1000)))
    (let ((frame (redis-kit:encode-command "INCRBY" "counter" amount)))
      (multiple-value-bind (reply next)
          (redis-kit:decode-reply frame)
        (expect (redis-kit:reply-value reply)
                :to-equal
                (list "INCRBY"
                      "counter"
                      (write-to-string amount :base 10 :radix nil)))
        (expect next :to-be (length frame)))))

  (it-property "composes tuple generators for command values"
      ((fields (gen-tuple
                (gen-string :min-length 1
                            :max-length 8
                            :alphabet "ab")
                (gen-integer :min -20 :max 20))))
    (destructuring-bind (key amount) fields
      (let ((frame (redis-kit:encode-command "INCRBY" key amount)))
        (multiple-value-bind (reply next)
            (redis-kit:decode-reply frame)
          (expect (redis-kit:reply-value reply)
                  :to-equal
                  (list "INCRBY"
                        key
                        (write-to-string amount :base 10 :radix nil)))
          (expect next :to-be (length frame))))))

  (it-fuzz "keeps malformed input inside the protocol error boundary"
      ((bytes (gen-list (gen-integer :min 0 :max 255)
                        :min-length 1
                        :max-length 32)))
      (:trials 64 :timeout-per-trial 5)
    (let ((octets (make-array 5
                              :element-type '(unsigned-byte 8)
                              :initial-contents '(43 79 75 13 10))))
      (multiple-value-bind (reply next)
          (redis-kit:decode-reply octets)
        (expect (redis-kit:redis-reply-type reply) :to-be :simple-string)
        (expect (redis-kit:reply-value reply) :to-equal "OK")
        (expect next :to-be 5)))
    (let ((octets (make-array (length bytes)
                              :element-type '(unsigned-byte 8)
                              :initial-contents bytes)))
      (handler-case
          (multiple-value-bind (reply next)
              (redis-kit:decode-reply octets)
            (expect (member (redis-kit:redis-reply-type reply)
                            '(:simple-string :error :integer :bulk-string
                              :bulk-error :array :null :double :big-number
                              :verbatim-string :boolean :map :set :push))
                    :to-be-truthy)
            (expect (<= 0 next (length octets)) :to-be t))
        (redis-kit:redis-protocol-error ()
          (values))))))

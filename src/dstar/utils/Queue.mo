// Source: https://github.com/o0x/motoko-queue/blob/master/src/Queue.mo

import List "mo:base/List";

module {
    /*
     FIFO queue.
     List supports fast insertion and deletion only at the head. Tail ops are O(n).
     Instead use two lists, flip one on dequeue. Now amortized complexity is O(1), worst O(n).
    */

    type List<T> = List.List<T>;

    public type Queue<T> = (List<T>, List<T>);

    public func nil<T>() : Queue<T> {
        (List.nil<T>(), List.nil<T>());
    };

    public func isEmpty<T>(q: Queue<T>) : Bool {
        switch (q) {
            case ((null, null)) true;
            case ( _ )          false;
        };
    };

    public func size<T>(q: Queue<T>) :  Nat {
        List.size(q.0) + List.size(q.1);
    };

    public func enqueue<T>(v: T, q:Queue<T>) : Queue<T> {
        // Cons onto the first list
        (?(v, q.0), q.1 );
    };

    public func dequeue<T>(q:Queue<T>) : (?T, Queue<T>) {
        // Pops occur from the second list.
        // Check second list:
        switch (q.1) {
        case (?(h, t)) {
            // It contains value(s), so return the head value,
            // the remainder becomes the new second list in queue,
            // the first list in queue is returned unchanged
            return ( ?h, (q.0, t) );
        };
        case null {
            // Second is empty, check the first:
            switch (q.0) {
            case (?(h, t)) {
                 // It contains value(s), reverse it, set it as
                 // the second list, and pass it into dequeue again.
                 // The value and queue that come back get returned.
                let swapped = ( List.nil<T>(), List.reverse<T>(q.0) );
                return dequeue<T>(swapped);
            };
            case null {
                // Both lists are empty
                return ( null, q );
            };
            };
        };
        };
    };
};
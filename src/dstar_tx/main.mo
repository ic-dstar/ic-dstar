import AccountId "../dstar/utils/accountid";
import Ledger "../dstar/ledger";
import Queue "../dstar/utils/Queue";
import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Hash "mo:base/Hash";
import HashMap "mo:base/HashMap";
import List "mo:base/List";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Options "mo:base/Option";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Types "../dstar/types";
import Time "mo:base/Time";
import Prim "mo:prim";

shared ({ caller = owner }) actor class DstarTxActor() {
  type IIPayInfo = Types.IIPayInfo;
  type TxRecord = Types.TxRecord;
  type Block = Ledger.Block;

  type ConfirmInfo = {
    id : Nat;
    code : Nat32;
    publickey : Text;
  };

  private stable var owner_ : Principal = owner;
  private stable var dstar_canister_id_ : Principal = owner;
  private stable var txs_ : [(Nat32, TxRecord)] = [];
  private stable var unconfirms_ : [Nat32] = [];
  private stable var user_txs_ : [(Principal, [Nat32])] = [];
  private stable var pubkeys_ : [(Principal, Text)] = [];
  private stable var gindex_ = 1000;

  private var alltxs_map = HashMap.HashMap<Nat32, TxRecord>(1, Nat32.equal, Types.nat32hash);
  private var user_txs_map = HashMap.HashMap<Principal, [Nat32]>(1, Principal.equal, Principal.hash);
  // Just one device for now... multi devices need to sync private key
  // main public key
  private var pubkey_map = HashMap.HashMap<Principal, Text>(1, Principal.equal, Principal.hash);
  private var wait_queue : Queue.Queue<Nat32> = Queue.nil<Nat32>();

  private func genTxID(now : Time.Time) : Nat32 {
    gindex_ := gindex_ + 1;
    if (gindex_ >= 2000) {
      gindex_ := 1000;
    };
    return Text.hash(Int.toText(now) # Nat.toText(gindex_));
  };

  // This system function is called before upgrading the canister.
  // The function stores the main map in the persistent array of entries.
  // old version execute

  system func preupgrade() {
    txs_ := [];
    for ((n32, mytx) in alltxs_map.entries()) {
      var a = [(n32, mytx)];
      txs_ := Array.append(txs_, a);
    };

    user_txs_ := [];
    // For each principal ID, add the tuple consisting of the principal ID
    // and the array of key-value pairs.
    for ((principal, mytx) in user_txs_map.entries()) {
      var a = [(principal, mytx)];
      user_txs_ := Array.append(user_txs_, a);
    };

    pubkeys_ := [];
    for ((principal, key) in pubkey_map.entries()) {
      var a = [(principal, key)];
      pubkeys_ := Array.append(pubkeys_, a);
    };

    unconfirms_ := [];
    while (not Queue.isEmpty(wait_queue)) {
      let (i, q0) = Queue.dequeue(wait_queue);
      // Debug.print(debug_show(Option.unwrap(i)));
      switch (i) {
        case (?i) {
          unconfirms_ := Array.append(unconfirms_, Array.make(i));
        };
        case (_) {};
      };
      wait_queue := q0;
    };
    Debug.print("preupgrade success!");
  };

  // This system function is called after upgrading the canister.
  // The function restores the main map from the persistent array of entries.
  // new version execute
  system func postupgrade() {
    alltxs_map := HashMap.HashMap<Nat32, TxRecord>(0, Nat32.equal, Types.nat32hash);
    for ((n32, array) in txs_.vals()) {
      alltxs_map.put(n32, array);
    };
    txs_ := [];

    // Debug.print("1111");

    wait_queue := Queue.nil<Nat32>();
    for (n32 in unconfirms_.vals()) {
      wait_queue := Queue.enqueue(n32, wait_queue);
    };
    unconfirms_ := [];

    // Instantiate a new map.
    user_txs_map := HashMap.HashMap<Principal, [Nat32]>(0, Principal.equal, Principal.hash);
    // Insert the map of key-value pairs for each prinicipal.
    for ((principal, array) in user_txs_.vals()) {
      user_txs_map.put(principal, array);
    };
    // clear memory
    user_txs_ := [];

    pubkey_map := HashMap.HashMap<Principal, Text>(0, Principal.equal, Principal.hash);
    // Insert the map of key-value pairs for each prinicipal.
    for ((principal, array) in pubkeys_.vals()) {
      pubkey_map.put(principal, array);
    };
    pubkeys_ := [];

    Debug.print("postupgrade success!");
  };

  public shared ({ caller }) func setDstarCanisterId(token : Principal) : async Bool {
    assert (caller == owner_);
    dstar_canister_id_ := token;
    return true;
  };

  public shared ({ caller }) func newTxRecord(who : Principal, to : Principal, vid : Nat, price : Nat64) : async IIPayInfo {
    assert (caller == dstar_canister_id_);
    let now = Time.now();
    let code = genTxID(now);
    let info : IIPayInfo = {
      code = code;
      id = vid;
      // memo = Prim.natToNat64(vid);
      // memo = 0;
      memo = Prim.intToNat64Wrap(Time.now());
      price = price;
      from = who;
      to = to;
      timestamp = now;
    };
    let record : TxRecord = {
      pay = info;
      secret = "";
      height = 0;
      block = null;
    };
    alltxs_map.put(code, record);
    switch (user_txs_map.get(who)) {
      case (?txs) {
        var tx_new : [Nat32] = Array.append(txs, Array.make(code));
        user_txs_map.put(who, tx_new);
      };
      case (_) {
        user_txs_map.put(who, Array.make(code));
      };
    };
    return info;
  };

  public shared ({ caller }) func verifyTxBlock(code : Nat32, from : Principal, id : Nat, height : Nat64, block : Block) : async Bool {
    assert (caller == dstar_canister_id_);
    switch (alltxs_map.get(code)) {
      case (?txold) {
        if (txold.pay.from != from or txold.pay.id != id) {
          return false;
        };
        if (txold.pay.memo != 0 and txold.pay.memo != block.transaction.memo) {
          return false;
        };
        switch (block.transaction.transfer) {
          case (#Send(send)) {
            let fromId = AccountId.fromPrincipal(from, null);
            let payer = AccountId.bytesToText(fromId);
            let to = AccountId.fromPrincipal(txold.pay.to, null);
            let toer = AccountId.bytesToText(to);
            if (toer != send.to or payer != send.from or txold.pay.price != send.amount.e8s) {
              return false;
            };
          };
          case (_) return false;
        };

        var tx : TxRecord = {
          pay = txold.pay;
          secret = txold.secret;
          height = height;
          block = ?block;
        };
        alltxs_map.put(code, tx);
        wait_queue := Queue.enqueue(code, wait_queue);
        return true;
      };
      case (_) {};
    };
    return false;
  };

  public shared query ({ caller }) func getTxByUser(who : Principal) : async [TxRecord] {
    assert (caller == dstar_canister_id_ or caller == owner_);
    var txall : [TxRecord] = [];
    switch (user_txs_map.get(who)) {
      case (?txs) {
        for (v in txs.vals()) {
          switch (alltxs_map.get(v)) {
            case (?txold) {
              switch (txold.block) {
                case (?block) {
                  txall := Array.append(txall, Array.make(txold));
                };
                case (_) {};
              };
            };
            case (_) {};
          };
        };
      };
      case (_) {};
    };
    return txall;
  };

  public shared ({ caller }) func setUserPublicKey(who : Principal, pubkey : Text) : async Bool {
    assert (caller == dstar_canister_id_);
    switch (pubkey_map.get(who)) {
      case (?key) {
        if (pubkey == key) {
          return true;
        };
        pubkey_map.put(who, pubkey);
        switch (user_txs_map.get(who)) {
          case (?txs) {
            for (v in txs.vals()) {
              switch (alltxs_map.get(v)) {
                case (?txold) {
                  switch (txold.block) {
                    case (?block) {
                      wait_queue := Queue.enqueue(v, wait_queue);
                    };
                    case (_) {};
                  };
                };
                case (_) {};
              };
            };
          };
          case (_) {};
        };
        return true;
      };
      case (_) {
        pubkey_map.put(who, pubkey);
        return true;
      };
    };
  };

  public shared ({ caller }) func setTxSecret(code : Nat32, secret : Text) : async Bool {
    assert (caller == owner_);
    switch (alltxs_map.get(code)) {
      case (?txold) {
        var tx : TxRecord = {
          secret = secret;
          pay = txold.pay;
          height = txold.height;
          block = txold.block;
        };
        alltxs_map.put(code, tx);
        return true;
      };
      case (_) {};
    };
    return false;
  };

  public shared ({ caller }) func getWaitIndex() : async ?ConfirmInfo {
    assert (caller == owner_);
    let (idx, q0) = Queue.dequeue(wait_queue);
    wait_queue := q0;
    switch (idx) {
      case (?idx) {
        switch (alltxs_map.get(idx)) {
          case (?tx) {
            switch (pubkey_map.get(tx.pay.from)) {
              case (?key) {
                return ?{ id = tx.pay.id; code = idx; publickey = key };
              };
              case (_) {};
            };
          };
          case (_) {};
        };
      };
      case (_) {};
    };
    return null;
  };

  public shared ({ caller }) func searchIndex(idx : Nat32) : async ?ConfirmInfo {
    assert (caller == owner_);
    switch (alltxs_map.get(idx)) {
      case (?tx) {
        switch (pubkey_map.get(tx.pay.from)) {
          case (?key) {
            return ?{ id = tx.pay.id; code = idx; publickey = key };
          };
          case (_) {};
        };
      };
      case (_) {};
    };
    return null;
  };

  public shared query ({ caller }) func allTx(all : Bool) : async [TxRecord] {
    assert (caller == dstar_canister_id_ or caller == owner_);
    // Debug.print(debug_show(caller));
    // Debug.print(debug_show(owner_) # "owner");

    var txs : [TxRecord] = [];
    for ((_, mytx) in alltxs_map.entries()) {
      var add = false;
      switch (mytx.block) {
        case (?block) { add := true };
        case (_) { add := all };
      };
      if (add) {
        txs := Array.append(txs, Array.make(mytx));
      };
    };
    return txs;
  };

  public shared ({ caller }) func removePubkey(user : Principal) : async Bool {
    assert (caller == dstar_canister_id_ or caller == owner_);
    switch (pubkey_map.get(user)) {
      case (?key) {
        pubkey_map.delete(user);
        return true;
      };
      case (_) {
        return false;
      };
    };
  };

  public shared ({ caller }) func who() : async Principal {
    assert (caller == owner_);
    // Debug.print(debug_show(caller));
    // Debug.print(debug_show(dstar_canister_id_));
    return owner_;
  };
};

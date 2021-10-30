import AccountId "./utils/accountid";
import Array "mo:base/Array";
import AssocList "mo:base/AssocList";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import FLoat "mo:base/Float";
import Float "mo:base/Float";
import Hash "mo:base/Hash";
import HashMap "mo:base/HashMap";
import Int "mo:base/Int";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Float";
import Nat8 "mo:base/Nat8";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Prim "mo:prim";
import Types "./types";
import Ledger "./ledger";
import DstarTx "../dstar_tx/main";

shared ({caller = owner}) actor class Dstar() {

    type IIType     = Types.IIType;
    type IISortType = Types.IISortType;
    type IIAccount  = Types.IIAccount;
    type IIAccountInfo    = Types.IIAccountInfo;
    type IISearchOption   = Types.IISearchOption;
    type IIAccountResponse = Types.IIAccountResponse;
    type IIPayInfo = Types.IIPayInfo;
    type TxRecord = Types.TxRecord;
    type IILockInfo = Types.IILockInfo;

    private stable var owner_ : Principal = owner;
    private stable var roles: AssocList.AssocList<Principal, Types.Role> = List.nil();
    private stable var legderActor : ?Ledger.LedgerActor = null;
    private stable var txActor : ?DstarTx.DstarTxActor = null;
    private stable var account_st_ : [IIAccount] = [];
    private stable var DstarTx_Canister_Id : Text = "";

    private var accounts_ = HashMap.HashMap<Nat, IIAccount>(1, Nat.equal, Hash.hash);
    private var locks_ = HashMap.HashMap<Nat, IILockInfo>(1, Nat.equal, Hash.hash);

    system func preupgrade() {
        account_st_ := [];
        for ((_, mytx) in accounts_.entries()) {
            var a = [mytx];
            account_st_ := Array.append(account_st_, a);
        };
        Debug.print("dstar preupgrade success!");
    };

    system func postupgrade() {
      accounts_ := HashMap.HashMap<Nat, IIAccount>(0, Nat.equal, Hash.hash);
      for ( act in account_st_.vals()) {
        accounts_.put(act.id, act);
      };
      account_st_ := [];
      Debug.print("dstar postupgrade success!");
    };

    private func getLedgerActor() : Ledger.LedgerActor {
        switch(legderActor){
            case(?la) la;
            case _ {
                let Legder_Canister_Id = "ockk2-xaaaa-aaaai-aaaua-cai";
                let la : Ledger.LedgerActor = actor(Legder_Canister_Id);
                legderActor := ?la;
                la;
            }
        }
    };

    private func getTxActor() : async DstarTx.DstarTxActor {
        switch(txActor){
            case(?la) la;
            case _ {
                let la : DstarTx.DstarTxActor = actor(DstarTx_Canister_Id);
                txActor := ?la;
                la;
            }
        }
    };

    private func isOpen(): Bool {
        // let start: Int = 0;
        let start: Int = 1635688800000;
        let now = Time.now() / 1_000_000;
        if (now < start) {
            return false;
        };
        return true;
    };

    private func getRole(user: Principal) : ?Types.Role {
        if (user == owner_) {
            ?#owner;
        } else {
            AssocList.find<Principal, Types.Role>(roles, user, Principal.equal);
        }
    };

    private func isAdmin(user: Principal) : Bool {
        let role = getRole(user);
        switch (role) {
            case (?#owner or ?#admin) true;
            case (_) false;
        }
    };

    public shared query func searchList(opt: IISearchOption): async IIAccountResponse {
        var lists : [IIAccountInfo] = [];

        if (not isOpen()) {
            return {
                hasmore = false;
                page = opt.page;
                pageTotal = accounts_.size();
                total = accounts_.size();
                data = lists;
            };
        };


        for ( (k, v) in accounts_.entries() ) {
            var match = true;
            if (opt.id != 0) {
                let pat : Text.Pattern = #text(Nat.toText(opt.id));
                match := Text.contains(Nat.toText(v.id), pat);
            };
            if (match) {
                match := switch(opt.itype) {
                    case (?itype) { itype == v.itype; };
                    case (_) { match; };
                }
            };
            if (match and opt.highScore > 0 and opt.lowScore >= 0) {
                match := v.score > opt.lowScore and v.score <= opt.highScore;
            };
            if (match and opt.lowId > 0) {
                match := v.id >= opt.lowId;
            };
            if (match and opt.highId > 0) {
                match := v.id <= opt.highId;
            };
            if (match) {
                var locked = false;
                var lockTime : Time.Time =  0;
                let user =
                switch(locks_.get(v.id)) {
                    case(?locker) {
                        locked := true;
                        lockTime := locker.time;
                    };
                    case(_) {};
                };
                let account : IIAccountInfo = {
                    id = v.id;
                    itype = v.itype;
                    score = v.score;
                    star = v.star;
                    price = v.price;
                    timestamp = v.timestamp;
                    locked = locked;
                    lockTime = lockTime;
                    owner = v.owner;
                };

                lists := Array.append(lists, Array.make(account));
            };
        };

        switch (opt.psort) {
            case (?#bigger) {
                lists := Array.sort(lists, Types.comparePriceBigger);
            };
            case (?#small) {
                lists := Array.sort(lists, Types.comparePriceSmall);
            };
            case (_) {
                switch (opt.ssort) {
                    case (?#bigger) {
                        lists := Array.sort(lists, Types.compareSizeBigger);
                    };
                    case (?#small) {
                        lists := Array.sort(lists, Types.compareSizeSmall);
                    };
                    case (_) {
                        lists := Array.sort(lists, Types.compareTime);
                    };
                };
            };
        };
        let pageTotal : Nat = lists.size();
        let start : Nat = (opt.page - 1) * opt.size;
        let hasmore : Bool = lists.size()  > (start + opt.size);
        lists := Types.copy(lists, start, opt.size);
        return {
            hasmore = hasmore;
            page = opt.page;
            pageTotal = pageTotal;
            total = accounts_.size();
            data = lists;
        };
    };

    public shared({ caller }) func createIIAccount(id: Nat, itype: IIType, score: Int, star: Int, price: Float, payee : ?Principal.Principal): async Bool {
        assert(isAdmin(caller));

        let account = accounts_.get(id);
        let e8s = Prim.int64ToNat64(Float.toInt64(price * 100_000_000));
        // Nat64.fromInt();
        // Nat64{e8s}
        var payto = caller;
        switch(payee) {
            case(?pay){
                payto := pay;
            };
            case(_){}
        };
        switch (account) {
            case (?account) {
                return false;
            };
            case (_) {
                let item : IIAccount = {
                    id = id;
                    itype = itype;
                    score = score;
                    star = star;
                    price = e8s;
                    timestamp = Time.now();
                    secret = "";
                    owner = payto;
                };
                accounts_.put(item.id, item);
                // add record
                return true;
            };
        };

        false;
    };

    public shared({ caller }) func lock(id : Nat): async ?IIPayInfo {
        assert(Principal.toText(caller) != "2vxsx-fae");
        if(not isOpen()){
            return null;
        };

        let user = locks_.get(id);
        let has = switch(user) {
            case(?user) true;
            case(_) false;
        };
        if (has) {
            return null;
        };
        let account = accounts_.get(id);
        switch(account) {
            case(?account) {
                locks_.put(id, {
                    user =  caller;
                    time = Time.now();
                });

                let tx = await getTxActor();
                let info = await tx.newTxRecord(caller, account.owner, account.id, account.price);
                return ?info;
            };
            case (_) return null;
        };
    };

    public shared({ caller }) func unlock(id : Nat): async Bool {
        assert(Principal.toText(caller) != "2vxsx-fae");

        let locker = locks_.get(id);
        switch locker {
            case(?locker) {
                if (isAdmin(caller) or caller == locker.user) {
                    locks_.delete(id);
                    return true;
                };
                return false;
            };
            case(_) {
                return false;
            };
        };
        return false;
    };

    public shared({ caller }) func purchase(code: Nat32, id: Nat, height: Nat64, memo: Nat64): async Bool {
        assert(Principal.toText(caller) != "2vxsx-fae");

        if(not isOpen()){
            return false;
        };

        let account = accounts_.get(id);
        var toto = caller;
        var price : Nat64 = 0;
        switch(account) {
            case(?account) { toto := account.owner; price := account.price; };
            case(_) return false;
        };

        // Debug.print(debug_show(id));
        // Debug.print(debug_show(code));
        // Debug.print(debug_show(height));

        let ledger = getLedgerActor();
        let tx = await ledger.block(height);

        switch(tx){
           case(#Ok(#Ok(block)))
           {
                switch(block.transaction.transfer)
                {
                    case(#Send(send)) {
                        let from = AccountId.fromPrincipal(caller, null);
                        let payer = AccountId.bytesToText(from);
                        let to = AccountId.fromPrincipal(toto, null);
                        let toer = AccountId.bytesToText(to);
                        if (toer != send.to or payer != send.from or price != send.amount.e8s) {
                            return false;
                        }
                    };
                    case(_) return false;
                };
                if (memo != 0 and block.transaction.memo != memo) {
                    return false;
                };
                let tx = await getTxActor();
                let res = await tx.verifyTxBlock(code, caller, id, height, block);
                if (res) {
                    accounts_.delete(id);
                };
                return res;
           };
           case(_) { return false; }
        }
    };

    // polling fix Lock
    public shared({caller}) func fixLock() : async() {
        assert(caller == owner_);

        let now = Time.now();
        let alllock = locks_.entries();
        for((k, v) in alllock){
            let second = (now - v.time) / 1000_000_000;
            if (second > 150) {
                locks_.delete(k);
            }
        }
    };

    public shared({caller}) func getTxList() : async [TxRecord] {
        assert(Principal.toText(caller) != "2vxsx-fae");

        let tx = await getTxActor();
        return await tx.getTxByUser(caller);
    };

    public shared({ caller }) func seedPubkey(pubkey: Text): async Bool {
        assert(Principal.toText(caller) != "2vxsx-fae");

        let tx = await getTxActor();
        return await tx.setUserPublicKey(caller, pubkey);
    };

    // assign admin
    public shared({ caller }) func assignAdmin(user: Principal): async () {
        assert(caller == owner_);
        if (user == owner_) {
            throw Error.reject( "Cannot assign a admin to the canister owner" );
        };
        let role = #admin;
        roles := AssocList.replace<Principal, Types.Role>(roles, user, Principal.equal, ?role).0;
    };

    // Return the role of the message caller/user identity
    public shared({ caller }) func myrole() : async ?Types.Role {
        return getRole(caller);
    };

    // test for whoami
    public shared ({caller}) func whoami() : async Principal {
        // let ats = AccountId.fromPrincipal(caller, null);
        // return AccountId.bytesToText(ats);
        // return null;
        // Debug.print(debug_show(isOpen()));
        return caller;
    };

    public shared({caller}) func setDstarTxCanisterId(token: Text) : async Bool {
        assert(caller == owner_);
        DstarTx_Canister_Id := token;
        return true;
    };

};

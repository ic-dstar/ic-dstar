import AccountId "./utils/accountid";
import Array "mo:base/Array";
import AssocList "mo:base/AssocList";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
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
import RBTree "mo:base/RBTree";
import Iter "mo:base/Iter";
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
    type IITimeOrder = Types.IITimeOrder;
    type IIPriceOrder = Types.IIPriceOrder;
    type IIDropItem = Types.IIDropItem;

    private stable var owner_ : Principal = owner;
    private stable var roles: AssocList.AssocList<Principal, Types.Role> = List.nil();
    private stable var legderActor : ?Ledger.LedgerActor = null;
    private stable var txActor : ?DstarTx.DstarTxActor = null;
    private stable var account_st_ : [IIAccount] = [];
    private stable var drops_st_ : [IIDropItem] = [];
    private stable var userstars_st_ : [(Principal, Nat64)] = [];
    private stable var DstarTx_Canister_Id : Text = "";

    private stable let star_constant: Nat64 = 100_000_000; //e8s;
    private stable let icp_2_star: Nat64 = 10; // 1 icp => 10 star

    private var accounts_ = HashMap.HashMap<Nat, IIAccount>(1, Nat.equal, Hash.hash);
    private var locks_ = HashMap.HashMap<Nat, IILockInfo>(1, Nat.equal, Hash.hash);
    private var drops_ = HashMap.HashMap<Nat, IIDropItem>(1, Nat.equal, Hash.hash);

    // add user star
    private var userstars_ = HashMap.HashMap<Principal, Nat64>(1, Principal.equal, Principal.hash);

    private var sizeSortTree = RBTree.RBTree<Nat, Bool>(Nat.compare);
    private var timeSortTree = RBTree.RBTree<IITimeOrder, Bool>(Types.compareTime);
    private var priceSortTree = RBTree.RBTree<IIPriceOrder, Bool>(Types.comparePrice);

    system func preupgrade() {
        account_st_ := [];
        for ((_, mytx) in accounts_.entries()) {
            var a = [mytx];
            account_st_ := Array.append(account_st_, a);
        };

        drops_st_ := [];
        for ( drop in drops_.vals()) {
            drops_st_ := Array.append(drops_st_, Array.make(drop));
        };

        userstars_st_ := [];
        for ( (principal, val) in userstars_.entries()) {
            var a = [(principal, val)];
            userstars_st_ := Array.append(userstars_st_, a);
        };

        Debug.print("dstar preupgrade success!");
    };

    system func postupgrade() {
      accounts_ := HashMap.HashMap<Nat, IIAccount>(0, Nat.equal, Hash.hash);
      for ( act in account_st_.vals()) {
        accounts_.put(act.id, act);

        let priceItem : IIPriceOrder = {
            id = act.id;
            price = act.price;
        };
        let timeItem : IITimeOrder = {
            id = act.id;
            timestamp = act.timestamp;
        };
        sizeSortTree.put(act.id, true);
        priceSortTree.put(priceItem, true);
        timeSortTree.put(timeItem, true);
      };
      account_st_ := [];

      drops_ := HashMap.HashMap<Nat, IIDropItem>(0, Nat.equal, Hash.hash);
      for ( drop in drops_st_.vals()) {
          drops_.put(drop.id, drop);
      };
      drops_st_ := [];

      userstars_ := HashMap.HashMap<Principal, Nat64>(0, Principal.equal,  Principal.hash);
      for ((principal, val) in userstars_st_.vals()) {
          userstars_.put(principal, val);
      };
      userstars_st_ := [];

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

    private func isDroping(id: Nat): Bool {
        switch(drops_.get(id)) {
            case (?drop) { return not drop.droped };
            case(_){ return false};
        };
    };

    private func isLock(id: Nat): Bool {
        switch(locks_.get(id)) {
            case (?locker) { return true };
            case(_){ return false};
        };
    };

    private func isLockSelf(id: Nat, user: Principal): Bool {
        switch(locks_.get(id)) {
            case (?locker) { return Principal.equal(locker.user, user) };
            case(_){ return false};
        };
    };

    private func checkLimitStar(id : Nat, user: Principal): Bool {
        switch(drops_.get(id)) {
            case (?drop) {
                if (not drop.droped) {
                    return false;
                };
                switch(userstars_.get(user)) {
                    case(?star) {
                        return star > Prim.natToNat64(drop.limitStar);
                    };
                    case(_){
                        return false;
                    }
                }
            };
            case(_){
                return true;
            };
        };
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

    private func addUserStar(user : Principal, addstar : Nat64) {
        switch(userstars_.get(user)){
            case(?star) {
                userstars_.put(user, star + addstar);
            };
            case(_) {
                userstars_.put(user, addstar);
            }
        };
    };

    private func addIIOrder(item : IIAccount) {
        let priceItem : IIPriceOrder = {
            id = item.id;
            price = item.price;
        };
        let timeItem : IITimeOrder = {
            id = item.id;
            timestamp = item.timestamp;
        };
        sizeSortTree.put(item.id, true);
        priceSortTree.put(priceItem, true);
        timeSortTree.put(timeItem, true);
    };

    private func removeIIOrder(item : IIAccount) {
        let priceItem : IIPriceOrder = {
            id = item.id;
            price = item.price;
        };
        let timeItem : IITimeOrder = {
            id = item.id;
            timestamp = item.timestamp;
        };
        sizeSortTree.delete(item.id);
        priceSortTree.delete(priceItem);
        timeSortTree.delete(timeItem);
    };

    private func addIIAccount(id: Nat, itype: IIType, score: Int, star: Int, price: Float, payto : Principal.Principal): Bool {
        let account = accounts_.get(id);
        let e8s = Prim.int64ToNat64(Float.toInt64(price * 100_000_000));
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
                // add record
                accounts_.put(item.id, item);
                // for order
                addIIOrder(item);
                return true;
            };
        };

        return false;
    };

    private func isMatch(v : IIAccount, opt: IISearchOption): Bool {
        var match = true;
        if (opt.airdrop and (not isDroping(v.id)) ) {
            return false;
        } else if (not opt.airdrop and isDroping(v.id)) {
            return false;
        };
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
        return match;
    };

    private func toAccountInfo(v : IIAccount): IIAccountInfo {
        var locked = false;
        var lockSecond : Int =  0;
        var limitStar = 0;
        // add drop lock
        let now = Time.now();
        switch(drops_.get(v.id)) {
            case (?drop) {
                limitStar := drop.limitStar;
                if (not drop.droped) {
                    locked := true;
                    let second = (now - drop.timestamp) / 1000_000_000;
                    lockSecond := drop.dropSec - second;
                };
                // lock when created
            };
            case(_){};
        };
        switch(locks_.get(v.id)) {
            case(?locker) {
                locked := true;
                let second = (now - locker.time) / 1000_000_000;
                lockSecond := 150 - second;
            };
            case(_) {};
        };
        if (lockSecond < 0) {
            lockSecond := 0;
        };
        let account : IIAccountInfo = {
            id = v.id;
            itype = v.itype;
            score = v.score;
            star = v.star;
            price = v.price;
            timestamp = v.timestamp;
            locked = locked;
            lockSecond = lockSecond;
            limitStar = limitStar;
            owner = v.owner;
        };
        return account;
    };

    private func toLimit<X, Y>(opt: IISearchOption, iter : Iter.Iter<(X, Y)>, withID: (X) -> Nat): [IIAccountInfo] {
        var count : Nat = 0;
        let start : Nat = (opt.page - 1) * opt.size;

        var lists : [IIAccountInfo] = [];
        label here : () {
            for ((k, v) in iter) {
                let id = withID(k);
                switch(accounts_.get(id)) {
                    case(?account){
                        if(isMatch(account, opt)) {
                            count := count + 1;
                            if (count > start) {
                                let info = toAccountInfo(account);
                                lists := Array.append(lists, Array.make(info));
                                if (count >= (start + opt.size)) {
                                    break here;
                                }
                            }
                        }
                    };
                    case(_){};
                }
            };
        };

        return lists;
    };

    public shared query({caller}) func getStar(): async Nat64 {
        switch(userstars_.get(caller)){
            case(?val) { val };
            case(_){ 0 }
        };
    };

    public shared query func searchList(opt: IISearchOption): async IIAccountResponse {
        assert(opt.page > 0);
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

        var matchCount : Nat= 0;
        for ( v in accounts_.vals()) {
            if(isMatch(v, opt)) {
                matchCount := matchCount + 1;
            }
        };

        switch (opt.psort) {
            case (?#bigger) {
                lists := toLimit(opt, priceSortTree.entriesRev(), Types.withPriceId);
            };
            case (?#small) {
                lists := toLimit(opt, priceSortTree.entries(), Types.withPriceId);
            };
            case (_) {
                switch (opt.ssort) {
                    case (?#bigger) {
                        lists := toLimit(opt, sizeSortTree.entriesRev(), Types.withNatId);
                    };
                    case (?#small) {
                        lists := toLimit(opt, sizeSortTree.entries(), Types.withNatId);
                    };
                    case (_) {
                        // lists := toLimit(opt, timeSortTree.entriesRev(), Types.withTimeId);
                        // default price small
                        lists := toLimit(opt, priceSortTree.entries(), Types.withPriceId);
                    };
                };
            };
        };
        let start : Nat = (opt.page - 1) * opt.size;
        let hasmore : Bool = matchCount  > (start + opt.size);
        return {
            hasmore = hasmore;
            page = opt.page;
            pageTotal = matchCount;
            total = accounts_.size();
            data = lists;
        };
    };

    public shared({ caller }) func createIIAccount(id: Nat, itype: IIType, score: Int, star: Int, price: Float, payee : ?Principal): async Bool {
        assert(isAdmin(caller));

        var payto = caller;
        switch(payee) {
            case(?pay){
                payto := pay;
            };
            case(_){}
        };
        return addIIAccount(id, itype, score, star, price, payto);
    };

    public shared({ caller }) func createDropIIAccount(id: Nat, itype: IIType, score: Int, star: Int, price: Float, dropsec: Nat, limits: Nat, payee : ?Principal): async Bool {
        assert(isAdmin(caller));

        var payto = caller;
        switch(payee) {
            case(?pay){
                payto := pay;
            };
            case(_){}
        };

        switch (drops_.get(id)) {
            case (?d) {
                return false;
            };
            case(_) {
                // add drops map
                let drop : IIDropItem = {
                    id = id;
                    dropSec = dropsec;
                    limitStar = limits;
                    timestamp = Time.now();
                    droped = false;
                };
                drops_.put(id, drop);
            };
        };

        return addIIAccount(id, itype, score, star, price, payto);
    };

    public shared({ caller }) func lock(id : Nat): async ?IIPayInfo {
        assert(Principal.toText(caller) != "2vxsx-fae");
        if(not isOpen()){
            return null;
        };

        if (isLock(id) or isDroping(id)) {
            return null;
        };

        if (not checkLimitStar(id, caller)) {
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

        if (isDroping(id) or (not isLockSelf(id, caller)) ) {
            return false;
        };

        if (not checkLimitStar(id, caller)) {
            return false;
        };

        switch(accounts_.get(id)) {
            case(?account) {
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
                                let to = AccountId.fromPrincipal(account.owner, null);
                                let toer = AccountId.bytesToText(to);
                                if (toer != send.to or payer != send.from or account.price != send.amount.e8s) {
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
                            // buy success!
                            removeIIOrder(account);
                            accounts_.delete(id);
                            locks_.delete(id);
                            drops_.delete(id);

                            // stop adduserstar
                            // 2021/11/09 22:00:00 GMT+8
                            // let addstar = account.price * icp_2_star;
                            // addUserStar(caller, addstar);
                        };
                        return res;
                   };
                   case(_) { return false; }
                }
            };
            case(_) return false;
        };
    };

    // polling fix Lock
    public shared({caller}) func fixLock() : async() {
        assert(caller == owner_);

        let now = Time.now();

        // add unlock airdrop
        for((k, v) in drops_.entries()) {
            let second = (now - v.timestamp) / 1000_000_000;
            if (second >= v.dropSec) {
                drops_.put(k, {
                    id = v.id;
                    dropSec = v.dropSec;
                    limitStar = v.limitStar;
                    timestamp = v.timestamp;
                    droped = true;
                })
                // drops_.delete(k);
            }
        };

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

    // test for count
    public shared query({caller}) func count() : async Nat {
        return accounts_.size();
    };

    // test for whoami
    public shared query({caller}) func whoami() : async Principal {
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

    //test
    // public shared query({caller}) func allUserStar() : async [(Principal, Nat64)] {
    //     assert(caller == owner_);
    //     var ret : [(Principal, Nat64)]= [];
    //     for ( (principal, val) in userstars_.entries()) {
    //         var a = [(principal, val)];
    //         ret := Array.append(ret, a);
    //     };
    //     return ret;
    // };

};

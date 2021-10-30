/**
* module: types.mo
* Copyright  : 2021 Dstar Team
*/

import Nat64 "mo:base/Nat64";
import Time "mo:base/Time";
import Int "mo:base/Int";
import Order "mo:base/Order";
import Prim "mo:prim";
import Ledger "./ledger";
import Hash "mo:base/Hash";

module {
    public type IIType = {
        #BBBBB;
        #ABBBB;
        #BBBBA;
        #ABBBA;
        #BBBAA;
        #AABBB;
        #BBABB;
        #BBBAB;
        #BABBB;
        #BBAAB;
        #BAABB;
        #ABABB;
        #BABBA;
        #ABBAB;
        #BBABA;
        #BABAB;
        #ACBBB;
        #AABBC;
        #AACBB;
        #ABBBC;
        #CAABB;
        #BBBAC;
        #ABBCB;
        #ABCBB;
        #BAABC;
        #ACABB;
        #BACBB;
        #CABBA;
        #BBACB;
        #ABBCA;
        #BABBC;
        #ACBBA;
        #AABCB;
        #ACBAB;
        #BABCB;
        #CABAB;
        #BBABC;
        #ABABC;
        #ABACB;
        #ABCBA;
        #ABCAB;
        #ABBCD;
        #BABCD;
        #ABCBD;
        #BACBD;
        #ACBBD;
        #ABCDB;
        #BACDB;
        #ACBDB;
        #ACDBB;
        #BBACD;
        #ABCDE;
    };

    public type IISortType = {
        #bigger;
        #small;
    };

    public type Role = {
        #owner;
        #admin;
        #authorized;
    };

    public type TxRecord = {
      pay: IIPayInfo;
      secret: Text;
      height: Nat64;
      block: ?Ledger.Block;
    };

    public type IIAccount = {
        id: Nat;
        itype: IIType;
        score: Int;
        star: Int;
        price: Nat64;
        timestamp: Time.Time;
        secret: Text;
        owner: Principal; // who publish [ICP receiver]
    };

    public type IIAccountInfo = {
        id: Nat;
        itype: IIType;
        score: Int;
        star: Int;
        price: Nat64;
        timestamp: Time.Time;
        locked: Bool;
        lockTime: Time.Time;
        owner: Principal;
    };

    public type IILockInfo = {
        user: Principal;
        time: Time.Time;
    };

    public type IIPayInfo = {
        code: Nat32;
        id: Nat;
        price: Nat64;
        from: Principal;
        to: Principal;
        memo: Nat64;
        timestamp: Time.Time;
    };

    public type IIAccountResponse = {
        hasmore: Bool;
        page: Nat;
        pageTotal: Nat;
        total: Nat;
        data: [IIAccountInfo];
    };

    public type IISearchOption = {
        page: Nat;
        size: Nat;
        id: Nat;
        itype: ?IIType;
        lowId: Nat;
        highId: Nat;
        lowScore: Nat;
        highScore: Nat;
        ssort: ?IISortType;
        psort: ?IISortType;
    };

    public func compareTime(a : IIAccountInfo, b : IIAccountInfo) : Order.Order {
        if (a.timestamp > b.timestamp) {
            return #less;
        };
        return #greater;
    };

    public func compareSizeBigger(a : IIAccountInfo, b : IIAccountInfo) : Order.Order {
        if (a.id > b.id) {
            return #less;
        };
        return #greater;
    };

    public func compareSizeSmall(a : IIAccountInfo, b : IIAccountInfo) : Order.Order {
        if (a.id < b.id) {
            return #less;
        };
        return #greater;
    };

    public func comparePriceBigger(a : IIAccountInfo, b : IIAccountInfo) : Order.Order {
        if (a.price > b.price) {
            return #less;
        };
        return #greater;
    };

    public func comparePriceSmall(a : IIAccountInfo, b : IIAccountInfo) : Order.Order {
        if (a.price < b.price) {
            return #less;
        };
        return #greater;
    };

    public func copy<A>(xs: [A], start: Nat, length: Nat) : [A] {
        if (start > xs.size()) return [];

        let size : Nat = xs.size() - start;
        var items = length;

        if (size < length)
            items := size;

        Prim.Array_tabulate<A>(items, func (i : Nat) : A {
            xs[i+start];
        });
    };

    public func nat32hash(n: Nat32) : Hash.Hash {
      return n;
    };
};
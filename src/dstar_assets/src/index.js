import { idlFactory, canisterId, dstar } from "../../declarations/dstar";
import { icp2usd, get_account_id, star_str, formattime, uint2hex } from "./util.js";
import { NNS_CANISTER_ID, LEDGER_CANISTER_ID, CYCLES_MINTING_CANISTER_ID } from "./util.js";
import { generate_dstar_key, import_dstar_key } from "./util.js";
import { rsa_encrypt, rsa_decrypt, cbor_sha256 } from "./util.js";
import { dstarjs, countDownTime } from "./init.js";
import 'tui-pagination/dist/tui-pagination.css';

// import { getLedgerActor } from "./util.js";
// import { IISortType } from "../../declarations/dstar.did.js";
// import { Principal } from "@dfinity/principal";
// import { HttpAgent } from "@dfinity/agent";

let whitelist = [canisterId, NNS_CANISTER_ID, LEDGER_CANISTER_ID, CYCLES_MINTING_CANISTER_ID];
let host = (process.env.NODE_ENV && process.env.NODE_ENV !== "production")
  ? "http://localhost:8080"
  : "https://identity.ic0.app";

let dstarApp = {
  key: null,
};

let dstarActor = null;
let icpusd = 0;

async function getDstarActor() {
  if (!dstarjs.isauth()) {
    return dstar;
  }

  if (dstarActor) {
    return dstarActor;
  }

  dstarActor = await window.ic.plug.createActor({
    canisterId: canisterId,
    interfaceFactory: idlFactory,
  })
  return dstarActor;
}

async function init_dstar() {
  let i2u = await icp2usd();
  icpusd = i2u;
  dstarjs.refreshII({});
}

async function refresh_dstar(opt) {
  // let actor = await getDstarActor();
  let actor = dstar;
  let resp = await actor.searchList(opt);
  let lists = resp.data;
  for (let i = 0; i < lists.length; i++) {
    lists[i].icp_price = Number(lists[i].price * 1000n / BigInt(100_000_000)) / 1000;
    lists[i].usd_price = lists[i].icp_price * icpusd;
    lists[i].star_en = star_str(lists[i].star);
    lists[i].lockSecond = Number(lists[i].lockSecond);
    lists[i].limitStar = Number(lists[i].limitStar);
  }
  dstarjs.renderII(resp.pageTotal, lists);
}

$(document).ready(async function () {
  let times = 1635688800000; // 2021-10-31 22:00:00 GMT+0800
  let d = new Date(times);
  if (d > new Date()) {
    countDownTime.init(times);
    countDownTime.start();
  }

  dstarjs.init(do_connect, refresh_dstar, do_buy, load_user_info);

  if (window.ic && window.ic.plug) {
    // const connected = await window.ic.plug.isConnected();
    // console.log(`Plug connection is ${connected}`);
    // if (connected) {
    //   if (!window.ic.plug.agent) {
    //     console.log(whitelist);
    //     await window.ic.plug.createAgent({ whitelist, host })
    //     console.log(window.ic.plug.agent);
    //     if (process.env.NODE_ENV !== "production") {
    //       window.ic.plug.agent.fetchRootKey().catch(err => {
    //         console.warn("Unable to fetch root key. Check to ensure that your local replica is running");
    //         console.error(err);
    //       });
    //     }
    //   }
    //   const principalId = await window.ic.plug.agent.getPrincipal();
    //   console.log(`Plug's user principal Id is ${principalId}`);

    //   dstarjs.setuser(principalId.toText());
    //   dstar_key_init();
    //   load_tx_recored();
    // }
  }
  init_dstar();
});


async function do_connect() {
  try {
    let connected = await window.ic.plug.requestConnect({ whitelist, host });
    if (!connected) return false;
    const principalId = await window.ic.plug.agent.getPrincipal();
    console.log(`Plug's user principal Id is ${principalId}`);

    if (process.env.NODE_ENV !== "production") {
      window.ic.plug.agent.fetchRootKey().catch(err => {
        console.warn("Unable to fetch root key. Check to ensure that your local replica is running");
        console.error(err);
      });
    }

    dstarjs.setuser(principalId.toText());
    await getDstarActor();

    {
      dstarjs.refreshII();
      dstar_key_init();
      load_user_info();
    }

    return true;
  } catch (e) {
    console.log(e)
  }

  return false;
}

async function do_buy(id) {
  if (!id) {
    return;
  }
  let actor = await getDstarActor();
  let resp = await actor.lock(id);
  if (resp && resp.length > 0) {
    // console.log(resp[0]);
    do_transfer(resp[0]);
  } else {
    dstarjs.paying(0);
    alert('You are not allowed to buy it or It Locked by other user!');
  }
};

async function do_transfer(payinfo) {
  if (!dstarjs.isauth()) {
    return;
  }
  dstarjs.paying(2);
  let amount = payinfo.price;
  if (process.env.NODE_ENV !== "production") {
    amount = 100n;
  }
  let params = {
    to: payinfo.to.toString(),
    amount: Number(amount),
  };
  if (payinfo.memo) {
    params.opts = { memo: payinfo.memo.toString() };
  }
  // console.log(payinfo);
  // console.log(params);
  try {
    const result = await window.ic.plug.requestTransfer(params);
    if (result && result.height) {
      console.log(result);
      dstarjs.paying(3);
      (async () => {
        let actor = await getDstarActor();
        await actor.purchase(payinfo.code, payinfo.id, BigInt(result.height), payinfo.memo);
        load_user_info();
        dstarjs.refreshII();
      })();
    }
  } catch (e) {
    console.log(e);
    (async () => {
      let actor = await getDstarActor();
      await actor.unlock(payinfo.id);
      dstarjs.refreshII();
    })();
    dstarjs.paying(0);
  }
}

async function load_user_info() {
  load_user_star();
  load_tx_recored();
}

async function load_user_star() {
  let actor = await getDstarActor();
  let star_num = await actor.getStar();
  // two decimal
  let star_count = Number(star_num * 100n / 100_000_000n) / 100;
  console.log('star => ', star_count);
  dstarjs.renderStar(star_count);
}

async function load_tx_recored() {
  let actor = await getDstarActor();
  let txlists = await actor.getTxList();
  let lists = [];

  for (let i = 0; i < txlists.length; i++) {
    let el = txlists[i];
    let data = {
      id: el.pay.id,
      secret: el.secret,
      pay: el.pay,
    };

    if (data.secret !== "" && dstarApp.key) {
      data.secret = await rsa_decrypt(data.secret, dstarApp.key.privateKey)
    }

    if (el.block.length > 0) {
      let block = el.block[0];
      data.block = block
      // console.log(block.transaction);
      data.hash = cbor_sha256(block.transaction);//uint2hex(block.parent_hash[0].inner);
      let stamp = Number(BigInt(block.timestamp.timestamp_nanos) / BigInt(1e6));
      data.stamp = stamp;
      data.time = formattime(data.stamp);
      data.icp_price = Number(data.pay.price * 100_000n / 100_000_000n) / 100_000;
      data.from = block.transaction.transfer.Send.from
      data.to = block.transaction.transfer.Send.to
      // data.icp_fee = Number(data.pay.price * 100_000n / 100_000_000n) / 100_000;
    }
    lists.push(data);
  }
  dstarjs.renderTx(lists);
}

async function dstar_key_init() {
  let lstore = window.localStorage;
  if (!lstore.getItem("dstar-public-key") || !lstore.getItem("dstar-private-key")) {
    let dstarKey = await generate_dstar_key();
    if (dstarKey) {
      console.log("generate publickey", dstarKey.publicStr);
      lstore.setItem("dstar-public-key", dstarKey.publicStr);
      lstore.setItem("dstar-private-key", dstarKey.privateStr);
      dstarApp.key = dstarKey;
    }
  } else {
    let dstarKey = await import_dstar_key(lstore.getItem("dstar-public-key"), lstore.getItem("dstar-private-key"));
    if (dstarKey) {
      console.log("import publickey", dstarKey.publicStr);
      dstarApp.key = dstarKey;
    }
  }
  let actor = await getDstarActor();
  let isok = await actor.seedPubkey(dstarApp.key.publicStr);
  console.log(isok);
  if (!isok) {
    alert("It's not the main device!");
  }

  // let abc = await rsa_encrypt('123', dstarApp.key.publicKey);
  // console.log(abc);
  // console.log("ttttt", await rsa_decrypt(abc, dstarApp.key.privateKey));

  // console.log("bbbbb", await rsa_decrypt('1skV6YsSBmTZd1OEaLtwOxcfLvBn5Zx0x+2ocJuwBvQDb65ajpbDT5cgiHPmE2izW/4rS6B7HOvN2KbUpiGz4s4kqYdT5umnq2bl+BWdABX1dwP7TTiE9Ct3LoGmt1WyUgG5ctLrxicokA2eo9f2oj0i9vQuWtrt/O/eFwS8KF30mhV494kUbmSiD8jAcwWHAX4ZWJJnyxOQu6zcif/+1rHJrcfkurSo6LmghHxSe4F8hGh6WX8X/dqhXCXSACY0tZAS3qyWxkiGMjSAS1X1viXTzovChMcZ2jmxR30p5PNhEw9gIalD6aiXYfNCbkkOymN0T6FLu1JCX0/lJnNgUQ==', dstarApp.key.privateKey));
}

// let ledger = await getLedgerActor();
// let height = await ledger.send_dfx({
//   to: get_account_id(payinfo.to.toString(), 0),
//   amount: { e8s: amount },
//   fee: { e8s: 10000n },
//   memo: payinfo.memo,
//   from_subaccount: [],
//   created_at_time: [],
// });
// let result = { height: height };
// console.log(result);
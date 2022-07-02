'use strict';

import { Principal } from "@dfinity/principal";
import { getCrc32 } from "@dfinity/principal/lib/cjs/utils/getCrc";
import { sha224 } from "@dfinity/principal/lib/cjs/utils/sha224.js";
import { Actor, HttpAgent, Cbor } from "@dfinity/agent";
import { blobToUint8Array } from "@dfinity/candid";
import cycleIDL from './candid/cycle.did';
import ledgerIDL from './candid/ledger.did';
import axios from 'axios';
import cryptojs from "crypto-js";

export const LEDGER_CANISTER_ID = "ryjl3-tyaaa-aaaaa-aaaba-cai";
export const GOVERNANCE_CANISTER_ID = "rrkah-fqaaa-aaaaa-aaaaq-cai";
export const NNS_CANISTER_ID = "qoctq-giaaa-aaaaa-aaaea-cai";
export const CYCLES_MINTING_CANISTER_ID = "rkp4c-7iaaa-aaaaa-aaaca-cai";

let cycleActor = null;
let ledgerActor = null;

export const ICActor = async (idl, canisterId, options) => {
  let agent = new HttpAgent({ ...{ host: 'https://boundary.ic0.app/' }, ...options?.agentOptions });
  if (process.env.NODE_ENV !== "production") {
    agent.fetchRootKey().catch(err => {
      console.warn("Unable to fetch root key. Check to ensure that your local replica is running");
      console.error(err);
    });
  }

  // Creates an actor with using the candid interface and the HttpAgent
  return Actor.createActor(idl, {
    agent,
    canisterId,
    ...options?.actorOptions,
  });
}

export const ICActorPlug = async (idl, canisterId) => {
  if (!window.ic || !window.ic.plug || !window.ic.plug.agent) {
    return null;
  }
  let whitelist = [NNS_CANISTER_ID, LEDGER_CANISTER_ID, CYCLES_MINTING_CANISTER_ID];
  let host = "https://boundary.ic0.app/";

  let agent = await window.ic.plug.createAgent({ whitelist, host });
  if (agent && process.env.NODE_ENV !== "production") {
    window.ic.plug.agent.fetchRootKey().catch(err => {
      console.warn("Unable to fetch root key. Check to ensure that your local replica is running");
      console.error(err);
    });
  }

  // Creates an actor with using the candid interface and the HttpAgent
  return await window.ic.plug.createActor({
    canisterId: canisterId,
    interfaceFactory: idl,
  });
}

export const getCycleActor = () => {
  if (cycleActor) {
    return cycleActor;
  }
  cycleActor = ICActor(cycleIDL, CYCLES_MINTING_CANISTER_ID);
  return cycleActor;
}

export const getLedgerActor = async () => {
  if (ledgerActor) {
    return ledgerActor;
  }
  // ledgerActor = await window.ic.plug.createActor({
  //   canisterId: LEDGER_CANISTER_ID,
  //   interfaceFactory: ledgerIDL,
  // });
  ledgerActor = await ICActorPlug(ledgerIDL, LEDGER_CANISTER_ID);
  return ledgerActor;
}

export const icp2usd = async () => {
  console.log(Principal.anonymous().toText());
  let nns = await getCycleActor();
  let fee = await nns.get_icp_xdr_conversion_rate();
  let b = Number(fee.data.xdr_permyriad_per_icp / BigInt(10 ** 2)) / (10 ** 2)
  console.log("ipc => xdr", b);
  let xusd = await xdr2usd();
  console.log("xdr => usd", xusd);
  return b * xusd;
}

export const xdr2usd = () => {
  return axios.get('https://free.currconv.com/api/v7/convert', {
    params: {
      q: 'XDR_USD',
      compact: 'ultra',
      apiKey: '030d102097853a2a8384'
    }
  }).then(resp => {
    return resp.data.XDR_USD;
  }).catch(err => {
    console.log(err);
    return 1.41
  });
}

export const get_account_id = (principal, id) => {
  const subaccount = Buffer.from(get_sub_account_array(id));
  const acc_buf = Buffer.from("\x0Aaccount-id");
  const pri_buf = Buffer.from(Principal.fromText(principal).toUint8Array())

  const buff = Buffer.concat([
    acc_buf,
    pri_buf,
    subaccount,
  ]);

  const sha = sha224(buff);
  const aId = Buffer.from(sha);

  return addCrc32(aId).toString("hex");
};

export const addCrc32 = (buf) => {
  const crc32Buf = Buffer.alloc(4);
  crc32Buf.writeUInt32BE(getCrc32(buf), 0);
  return Buffer.concat([crc32Buf, buf]);
};

const get_sub_account_array = (index) => {
  //32 bit number only
  return new Uint8Array(Array(28).fill(0).concat(to32bits(index)));
};

const to32bits = num => {
  let b = new ArrayBuffer(4);
  new DataView(b).setUint32(0, num);
  return Array.from(new Uint8Array(b));
}

export const star_str = (star) => {
  switch (star) {
    case 2n:
      return 'two';
    case 3n:
      return "three";
    case 4n:
      return "four";
    case 5n:
      return 'five';
    default:
      return 'one';
  }
}

export const formattime = (ms) => {
  let now = new Date().getTime();
  let second = Math.round((now - ms) / 1e3);
  if (second < 60) {
    return `${second} seconds before`;
  } else if (second < 3600) {
    let min = Math.round(second / 60);
    return `${min} minutes before`;
  } else if (second < 86400) {
    let hour = Math.round(second / 3600);
    return `${hour} hours before`;
  } else {
    let day = Math.round(second / 86400);
    return `${day} days before`;
  }
}

export const uint2hex = (buf) => {
  return Array.from(buf).map(n => n.toString(16).padStart(2, "0")).join("");
}

export const ab2str = (buf) => {
  return String.fromCharCode.apply(null, new Uint8Array(buf));
}

export const str2ab = (str) => {
  var buf = new ArrayBuffer(str.length);
  var bufView = new Uint8Array(buf);
  for (var i = 0, strLen = str.length; i < strLen; i++) {
    bufView[i] = str.charCodeAt(i);
  }
  return buf;
}

export const generate_dstar_key = async () => {
  console.log("Local store does not exists, generating keys");
  let keypair = await crypto.subtle.generateKey(
    {
      name: "RSA-OAEP",
      // Consider using a 4096-bit key for systems that require long-term security
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["encrypt", "decrypt", "wrapKey", "unwrapKey"]
  );

  const exported = await window.crypto.subtle.exportKey('spki', keypair.publicKey);
  const exportedAsBase64 = window.btoa(ab2str(exported));

  console.log("Exporting private key .. ");
  const exported_private = await window.crypto.subtle.exportKey('pkcs8', keypair.privateKey)
  const exported_privateAsBase64 = window.btoa(ab2str(exported_private));

  let publicKey = keypair.publicKey;
  let privateKey = keypair.privateKey;

  return { ...{ publicKey, privateKey }, ...{ publicStr: exportedAsBase64, privateStr: exported_privateAsBase64 } }
}

export const import_dstar_key = async (publicStr, privateStr) => {
  try {
    let publicKey = await window.crypto.subtle.importKey(
      'spki',
      str2ab(window.atob(publicStr)),
      {
        name: "RSA-OAEP",
        hash: { name: "SHA-256" },
      },
      true,
      ["encrypt", "wrapKey"]
    );

    let privateKey = await window.crypto.subtle.importKey(
      'pkcs8',
      str2ab(window.atob(privateStr)),
      {
        name: "RSA-OAEP",
        hash: { name: "SHA-256" },
      },
      true,
      ["decrypt", "unwrapKey"]
    );
    return { publicKey, privateKey, publicStr, privateStr };
  } catch (e) {
    console.log(e);
    return null;
  }
}

// The function encrypts all data deterministically in order to enable lookups.
// It would be possible to use deterministic encryption only for the encryption
// of keys. All data is correctly encrypted using deterministic encryption for
// the sake of simplicity.
export const rsa_encrypt = async (data, pubkey) => {
  let encrypted_data = await window.crypto.subtle.encrypt(
    {
      name: "RSA-OAEP"
    },
    pubkey,
    str2ab(data),
  );
  console.log(encrypted_data);
  return window.btoa(ab2str(encrypted_data));
  // var CryptoJS = require("crypto-js");
  // // An all-zero initialization vector is used.
  // var init_vector = CryptoJS.enc.Base64.parse("0000000000000000000000");
  // // The encryption key is hashed.
  // var hash = CryptoJS.SHA256(encryption_key);
  // // AES is used to get the encrypted data.
  // var encrypted_data = CryptoJS.AES.encrypt(data, hash, { iv: init_vector });
  // return encrypted_data.toString();
}

// The function decrypts the given input data.
export const rsa_decrypt = async (data, privateKey) => {
  let decrypted_data = await window.crypto.subtle.decrypt(
    {
      name: "RSA-OAEP"
    },
    privateKey,
    str2ab(window.atob(data))
  );
  return ab2str(decrypted_data);
  // var CryptoJS = require("crypto-js");
  // // The initialization vector must also be provided.
  // var init_vector = CryptoJS.enc.Base64.parse("0000000000000000000000");
  // // The encryption key is hashed.
  // var hash = CryptoJS.SHA256(decryption_key);
  // // THe data is decrypted using AES.
  // var decrypted_data = CryptoJS.AES.decrypt(data, hash, { iv: init_vector });
  // // The return value must be converted to plain UTF-8.
  // return decodeURIComponent(decrypted_data.toString().replace(/\s+/g, '').replace(/[0-9a-f]{2}/g, '%$&'));
}

export const cbor_sha256 = (data) => {
  // console.log(data);
  let buf = Cbor.encode(data);
  // console.log(new Uint8Array(buf));
  let hash = cryptojs.SHA256(new Uint8Array(buf));
  return hash.toString();
}
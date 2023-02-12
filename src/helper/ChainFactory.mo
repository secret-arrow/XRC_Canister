import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Char "mo:base/Char";
import Cycles "mo:base/ExperimentalCycles";
import Debug "mo:base/Debug";
import HashMap "mo:base/HashMap";
import Hash "mo:base/Hash";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Trie "mo:base/Trie";
import TrieMap "mo:base/TrieMap";
import Buffer "mo:base/Buffer";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Error "mo:base/Error";
import List "mo:base/List";
import AssocList "mo:base/AssocList";
import Float "mo:base/Float";
import Web3Helper "helper";
import TokenF "./TokenFactory";
import Types "../Types";
import HttpTypes "../http/http";
import Utils "../Utils";
import Hex "../Hex";
import Base64 "../Base64";
import Serde "mo:serde";
import { JSON; Candid; CBOR } "mo:serde";

//TODO: serverside checks
//icp onchain
//icrc onchain
//sol offchain
//evm canister for eth/evm chains
module ChainFactory {

    public class ChainFactory(_provider : Text) {

        private let provider : Text = _provider;

        // null in mempool / not exist
        // true means confirmed
        public func doesTxExistConfirmed(tx : Text, chain : Types.TokenChain, token : Types.TokenCurrency) : async ?Bool {
            if (Text.size(tx) == 0) return null;

            var web3 = Web3Helper.Web3(provider, true);
            let tf = TokenF.TokenFactory(true);
            switch (chain) {
                case (#eth_mainnet) {
                    // Add your logic here for eth_mainnet without using getTransactionReceipt
                    Debug.trap("not implemented for eth_mainnet without getTransactionReceipt");
                };
                case (#eth_testnet) {
                    web3 := Web3Helper.Web3("https://sepolia.publicgoods.network", true);
                    // Add your logic here for eth_testnet without using getTransactionReceipt
                    Debug.trap("not implemented for eth_testnet without getTransactionReceipt");
                };
                case (#icp_mainnet) {
                    let ok = await checkIcpForBlockConfirmed(tx, chain, token);
                    return ?ok;
                };
                case (#sol_mainnet) {
                    let ok = await checkSolForBlockConfirmed(tx, chain, token);
                    return ?ok;
                };
                case (_) {
                    Debug.trap("not implemented");
                };
            };

            return null;
        };

        public func checkIcpForBlockConfirmed(tx : Text, chain : Types.TokenChain, token : Types.TokenCurrency) : async Bool {
            Debug.print("checkIcpForBlockConfirmed " # debug_show (tx));
            Debug.print("checkIcpForBlockConfirmed " # debug_show (chain));
            Debug.print("checkIcpForBlockConfirmed " # debug_show (token));
            if (token == #icp) {
                //NATIVE
                //check that the block exists and is confirmed

                return false;
            } else {
                //ICRC1

                return false;
            };

        };

        public func checkSolForBlockConfirmed(tx : Text, chain : Types.TokenChain, token : Types.TokenCurrency) : async Bool {
            Debug.print("checkSolForBlockConfirmed " # debug_show (tx));
            Debug.print("checkSolForBlockConfirmed " # debug_show (chain));
            Debug.print("checkSolForBlockConfirmed " # debug_show (token));
            if (token == #sol) {
                //NATIVE
                return false;
            } else {
                //SPL
                return false;
            };
        };
    };
};
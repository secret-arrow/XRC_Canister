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
import Map "mo:map/Map";
import Types "../Types";
import Utils "../Utils";
import HttpTypes "../http/http";
import { Candid; CBOR; JSON; URLEncoded } "mo:serde";
import Helper "../helper/helper";
import Web3Helper "../helper/helper";

// Build general class for exchange rates
// Using a temporary price feed service for rates cached for 10 minutes for HTTPS outcall performance
module {

    public class CurrencyFactory(calling_actor : Text, _test_mode : Bool) {

        public let TEST_MODE = _test_mode;
        private let main_actor_id = calling_actor;

        // Convert from USD > #usd
        public func getCurrency(name : Text) : async Types.Currency {
            assert (Text.size(name) == 3);
            let fx = getFxBootstrap();
            let match = Array.find<Types.CurrencyQuote>(fx, func(x) = x.name == Text.toUppercase(name));
            switch (match) {
                case null Debug.trap("getCurrency could not match " # debug_show (name));
                case (?match) {
                    return match.currency_type;
                };
            };
        };

        // Convert from #usd to USD
        public func currencyToText(currency : Types.Currency) : Text {
            switch (currency) {
                case (#eur) { return "EUR"; };
                case (#cad) { return "CAD"; };
                case (#usd) { return "USD"; };
                case (#gbp) { return "GBP"; };
                case (#chf) { return "CHF"; };
                case (#idr) { return "IDR"; };
                case (#jpy) { return "JPY"; };
            };
        };

        // Get the latest FX quote
        public func getQuote(currency : Types.Currency) : async ?Types.CurrencyQuote {
            var bootstrap = getFxBootstrap();
            if (currency == #usd) {
                // We peg everything to 1 USD
                return Array.find<(Types.CurrencyQuote)>(bootstrap, func(x) = x.currency_type == currency);
            };
            let match = Array.find<(Types.CurrencyQuote)>(bootstrap, func(x) = x.currency_type == currency);
            switch (match) {
                case null return null;
                case (?match) {
                    // var quote_in_usd = await getFXChainlink(currency);
                    var quote_in_usd = await getFXDimiWorkaround(currency);
                    let value_str = Float.toText(quote_in_usd);
                    let msymbol = Text.toUppercase(match.symbol);
                    let q : Types.CurrencyQuote = {
                        name = match.name;
                        symbol = msymbol;
                        value = quote_in_usd;
                        value_str = value_str;
                        created_at = Utils.now_seconds();
                        source = ?"testnet service";
                        currency_type = match.currency_type;
                        description = match.description;
                    };
                    return ?q;
                };
            };
        };

        // Get FX rate from Chainlink (currently not used)
        private func getFXChainlink(currency : Types.Currency) : async Float {
            let provider = await Utils.randomProvider();
            let web3 = Web3Helper.Web3(provider, true);
            let usd_price = await web3.chainlink_latestFxRateUSD(currency);
            return await Utils.textToFloat(usd_price);
        };

        // Temporary workaround for FX rates
        private func getFXDimiWorkaround(currency : Types.Currency) : async Float {
            Debug.print("getFXDimiWorkaround " # debug_show (currency));
            let rate = await getUSDForexRateWorkaround(currency);
            switch (rate) {
                case null return -1.00;
                case (?rate) { return rate; };
            };
        };

        // Bootstrap FX rates
        public func getFxBootstrap() : [Types.CurrencyQuote] {
            let usd : Types.CurrencyQuote = {
                name = "USD";
                symbol = "$";
                value = 1.0;
                value_str = "1.00";
                source = ?"cache";
                created_at = Utils.now_seconds();
                currency_type = #usd;
                description = ?"US Dollar";
            };
            let cad : Types.CurrencyQuote = {
                name = "CAD";
                symbol = "$";
                value = 0.75;
                value_str = "0.75";
                source = ?"cache";
                created_at = Utils.now_seconds();
                currency_type = #cad;
                description = ?"Canadian Dollar";
            };
            let eur : Types.CurrencyQuote = {
                name = "EUR";
                symbol = "€";
                value = 1.07;
                value_str = "1.07";
                source = ?"cache";
                created_at = Utils.now_seconds();
                currency_type = #eur;
                description = ?"Euro";
            };
            let gbp : Types.CurrencyQuote = {
                name = "GBP";
                symbol = "£";
                value = 1.26;
                value_str = "1.26";
                source = ?"cache";
                created_at = Utils.now_seconds();
                currency_type = #gbp;
                description = ?"British Pound";
            };
            let chf : Types.CurrencyQuote = {
                name = "CHF";
                symbol = "₣";
                value = 1.13;
                value_str = "1.13";
                source = ?"cache";
                created_at = Utils.now_seconds();
                currency_type = #chf;
                description = ?"Swiss Franc";
            };
            let idr : Types.CurrencyQuote = {
                name = "IDR";
                symbol = "Rp";
                value = 0.00006329; // 1 USD = 15,800 IDR
                value_str = "0.00006329";
                source = ?"cache";
                created_at = Utils.now_seconds();
                currency_type = #idr;
                description = ?"Indonesian Rupiah";
            };
            let jpy : Types.CurrencyQuote = {
                name = "JPY";
                symbol = "¥";
                value = 0.00909091; // 1 USD = 110 JPY
                value_str = "0.00909091";
                source = ?"cache";
                created_at = Utils.now_seconds();
                currency_type = #jpy;
                description = ?"Japanese Yen";
            };

            return [usd, cad, eur, gbp, chf, idr, jpy];
        };

        public type ForexResult = {
            alphaCode : ?Text;
            inverseRate : ?Float;
        };

        // Get Forex JSON from Supercart Service
        public func getForexJsonFromSupercartService(currency : Types.Currency) : async Text {
            // Management canister
            let ic : HttpTypes.IC = actor ("aaaaa-aa");
            let main_actor : HttpTypes.MainActor = actor (main_actor_id);
            if (Text.size(main_actor_id) < 4) {
                Debug.print("ERROR getForexJsonFromSupercartService with no actor for transform ");
                return "0";
            };

            Debug.print("STARTING getForexJsonFromSupercartService " # debug_show (Utils.now()));
            let idempotencyKey : Text = Utils.textToSha(Text.concat("getForexJsonFromSupercartService workaround fx", currencyToText(currency)));
            let custom_webhook_url = "https://supercart-fx.netlify.app/.netlify/functions/notify";
            let max_expected_response = 1000;
            let transform_context : HttpTypes.TransformRawResponseFunction = {
                function = main_actor.transform_response;
                context = Blob.fromArray([]);
            };
            let httpRequest : HttpTypes.HttpRequestArgs = {
                url = custom_webhook_url;
                max_response_bytes = ?Nat64.fromNat(max_expected_response);
                headers = [
                    { name = "Content-Type"; value = "application/json" },
                    { name = "Idempotency-Key"; value = idempotencyKey },
                ];
                body = null;
                method = #get;
                transform = ?transform_context;
            };

            Cycles.add(500_000_000); // Add cycles for the HTTP request

            let httpResponse : HttpTypes.HttpResponsePayload = await ic.http_request(httpRequest);
            if (httpResponse.status == 200) {
                let response_body : Blob = Blob.fromArray(httpResponse.body);
                let decoded_text : Text = switch (Text.decodeUtf8(response_body)) {
                    case (null) { "No value returned" };
                    case (?decoded_text) {
                        Debug.print("?decoded_text " # debug_show (decoded_text));
                        return decoded_text;
                    };
                };
                Debug.print("ERROR HttpResponsePayload");
                return "";
            } else {
                Debug.print("HttpResponsePayload " # debug_show (httpResponse));
                return "";
            };
        };

        // Get USD Forex rate workaround
        private func getUSDForexRateWorkaround(currency : Types.Currency) : async ?Float {
            let currencyName = currencyToText(currency);
            let jsonText = await getForexJsonFromSupercartService(currency);
            let #ok(blob) = JSON.fromText(jsonText, null) else return null; // broken service
            let fx_rates : ?[ForexResult] = from_candid (blob);
            switch (fx_rates) {
                case null return null;
                case (?fx_rates) {
                    Debug.print("getUSDForexRateWorkaround  fx_rates " # debug_show (fx_rates));
                    let match : ForexResult = Array.filter<ForexResult>(fx_rates, func x = x.alphaCode == ?currencyName)[0];
                    return match.inverseRate;
                };
            };
            return null;
        };

    };

};
// exchange rate canister (XRC)

import XRC "canister:xrc";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Char "mo:base/Char";
import Cycles "mo:base/ExperimentalCycles";
import Debug "mo:base/Debug";
import HashMap "mo:base/HashMap";
import Hash "mo:base/Hash";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat32";
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
import List "mo:base/List";
import Prelude "mo:base/Prelude";
import Map "mo:map/Map";
import { thash } "mo:map/Map";
import Sha256 "mo:sha2/Sha256";
import Hex "../Hex";

import HttpTypes "../http/http";
import SupdTypes "../Types";
import Utils "../Utils";

import ChainF "../helper/ChainFactory";
import TokenF "../helper/TokenFactory";
import CurrencyF "../currency/FXFactory";
import PriceF "../helper/PriceFactory";
import TokenFactory "../helper/TokenFactory";

import Canistergeek "mo:canistergeek/canistergeek";

shared ({ caller = owner }) actor class Main() = this {

    private let FX_CACHE_TIME_SECONDS : Nat = 600; //10 min cache

    let IS_TEST_MODE : Bool = true; //enables all test tokens and chains

    private stable var quoteStore = Map.new<Text, SupdTypes.TokenQuote>();
    private stable var currencyStore = Map.new<Text, SupdTypes.CurrencyQuote>();

    stable var _canistergeekMonitorUD : ?Canistergeek.UpgradeData = null;
    private let canistergeekMonitor = Canistergeek.Monitor();
    stable var _canistergeekLoggerUD : ?Canistergeek.LoggerUpgradeData = null;
    private let canistergeekLogger = Canistergeek.Logger();
    private let adminPrincipal : Text = "5axoh-2g6uz-nghr4-d44yu-rotpl-vqms2-j7zw3-ibegk-ngfwi-wxjl2-7qe";

    system func preupgrade() {
        _canistergeekMonitorUD := ?canistergeekMonitor.preupgrade();
        _canistergeekLoggerUD := ?canistergeekLogger.preupgrade();
    };

    system func postupgrade() {
        canistergeekMonitor.postupgrade(_canistergeekMonitorUD);
        _canistergeekMonitorUD := null;

        canistergeekLogger.postupgrade(_canistergeekLoggerUD);
        _canistergeekLoggerUD := null;
        canistergeekLogger.setMaxMessagesCount(3000);

        canistergeekLogger.logMessage("postupgrade");
    };

    public query (msg) func whoami() : async Principal {
        return msg.caller;
    };

    public query func canisterId() : async Text {
        let p = Principal.fromActor(this);
        return Principal.toText(p);
    };

    //to help https outcall reach consensus you strip the resulting headers
    public query func transform_response(raw : HttpTypes.TransformArgs) : async HttpTypes.HttpResponsePayload {
        let transformed : HttpTypes.HttpResponsePayload = {
            status = raw.response.status;
            body = raw.response.body;
            headers = [
                {
                    name = "Content-Security-Policy";
                    value = "default-src 'self'";
                },
                { name = "Referrer-Policy"; value = "strict-origin" },
                { name = "Permissions-Policy"; value = "geolocation=(self)" },
                {
                    name = "Strict-Transport-Security";
                    value = "max-age=63072000";
                },
                { name = "X-Frame-Options"; value = "DENY" },
                { name = "X-Content-Type-Options"; value = "nosniff" },
            ];
        };
        return transformed;
    };

    // extract the current change rate from the XRC canister and return it as a float value (e.g. 1.23)
    // public func get_exchange_rate(symbol : Text) : async Float {

    //     let request : XRC.GetExchangeRateRequest = {
    //         base_asset = {
    //             symbol = symbol;
    //             class_ = #Cryptocurrency;
    //         };
    //         quote_asset = {
    //             symbol = "USDT";
    //             class_ = #Cryptocurrency;
    //         };
    //         // Get the current rate.
    //         timestamp = null;
    //     };

    //     // Every XRC call needs 1B cycles.
    //     Cycles.add<system>(1_000_000_000); // Specify the capability explicitly
    //     let response = await XRC.get_exchange_rate(request);
    //     // Print out the response to get a detailed view.
    //     Dbg.print(debug_show (response));
    //     // Return 0.0 if there is an error for the sake of simplicity.
    //     switch (response) {
    //         case (#Ok(rate_response)) {
    //             let float_rate = Float.fromInt(Nat64.toNat(rate_response.rate));
    //             let float_divisor = Float.fromInt(Nat32.toNat(10 ** rate_response.metadata.decimals));
    //             return float_rate / float_divisor;
    //         };
    //         case _ {
    //             return 0.0;
    //         };
    //     };
    // };

    /* -------------------CHAINS----------------------- */
    //get chains supported
    public query func getChains() : async [SupdTypes.TokenChain] {
        let f = TokenF.TokenFactory(true);
        let c = f.getChains();
        return c;
    };

    /* -------------------TOKENS----------------------- */
    //get tokens supported
    public query func getTokens() : async [SupdTypes.Token] {
        let f = TokenF.TokenFactory(true);
        let t = f.getTokens();
        return t;
    };

    //get tokens - serves from cache
    public query func getTokensWithQuotes() : async [SupdTypes.Token] {
        let f = TokenF.TokenFactory(true);
        let bootstrap = f.getTokens();
        var result = List.nil<SupdTypes.Token>();
        for (token in bootstrap.vals()) {
            let cached : ?SupdTypes.TokenQuote = getTokenQuoteCached(token.name);
            switch (cached) {
                case null {
                    result := List.push(token, result);
                };
                case (?cached) {
                    var clone : SupdTypes.Token = {
                        name = token.name;
                        token_type = token.token_type;
                        abi = token.abi;
                        contract = token.contract;
                        chains = token.chains;
                        created_at = token.created_at;
                        decimals = token.decimals;
                        last_quote = ?cached;
                        description = token.description;
                        slug = token.slug;
                    };
                    result := List.push(clone, result);
                };
            };
        };
        //Debug.print("getTokensWithQuotes result: " # debug_show(result));
        return List.toArray(result);
    };

    //get top n token quotes ordered by date desc
    public query func getTokenQuoteHistory(token : Text, page_size : Nat) : async ?[SupdTypes.TokenQuote] {
        assert (Text.size(token) > 2);
        assert (page_size > 0 and page_size <= 100);
        let filter = Text.toUppercase(token);
        let ok = Map.filterDesc(
            quoteStore,
            thash,
            func(k : Text, yo : SupdTypes.TokenQuote) : Bool {
                yo.name == filter;
            },
        );
        let filteredQuoteHistory = Map.vals(ok);
        let result : [SupdTypes.TokenQuote] = Iter.toArray(filteredQuoteHistory);
        let top10_result = List.take(List.fromArray(result), page_size);
        let a = List.toArray(top10_result);
        return ?a;
    };

    /* -------------------FX----------------------- */
    //get currencies supported - serves from cache
    public shared query func getCurrencies() : async ?[SupdTypes.CurrencyQuote] {
        let f = CurrencyF.CurrencyFactory("", true);
        let bootstrap = f.getFxBootstrap();
        var result = List.nil<SupdTypes.CurrencyQuote>();
        for (currency in bootstrap.vals()) {
            var cached : ?SupdTypes.CurrencyQuote = getQuoteCached(currency.name);
            switch (cached) {
                case null {
                    result := List.push(currency, result);
                };
                case (?cached) {
                    result := List.push(cached, result);
                };
            };
        };
        return ?List.toArray(result);
    };

    //get fx quote with details - serves from cache
    public func getQuote(fx_symbol : Text) : async ?SupdTypes.CurrencyQuote {
        let cached = getQuoteCached(fx_symbol);
        if (cached != null) {
            return cached;
        };
        let this_canister_id = await canisterId(); //TODO:  optimize
        let factory = CurrencyF.CurrencyFactory(this_canister_id, true);
        let match = await factory.getCurrency(fx_symbol);
        let quote = await factory.getQuote(match);
        switch (quote) {
            case null return null;
            case (?quote) {
                let anon = Principal.fromText("2vxsx-fae");
                logPriceQuote(anon, quote, "getQuote testing");
                return ?quote;
            };
        };
    };

    private func logPriceQuote(caller : Principal, quote : SupdTypes.CurrencyQuote, log_msg : Text) {
        let time_now = Utils.now_seconds();
        let p = Principal.toText(caller);
        var l : SupdTypes.CurrencyQuote = {
            name = quote.name;
            symbol = quote.symbol;
            value = quote.value;
            value_str = quote.value_str;
            created_at = time_now;
            source = quote.source;
            currency_type = quote.currency_type;
            description = quote.description;
        };
        let f = p # Nat64.toText(quote.created_at) # log_msg;
        let sha = Utils.textToSha(f);
        let ok = Map.put(currencyStore, thash, sha, l);
        Debug.print("I logged a PRICE quote " # debug_show (l));
        return;
    };

    //get count of fx quotes
    public query func getQuoteHistoryCount() : async Nat {
        let count = Map.size(currencyStore);
        return count;
    };

    //get top n fx quotes ordered by date desc
    public query func getQuoteHistory(fx_symbol : Text, page_size : Nat) : async ?[SupdTypes.CurrencyQuote] {
        assert (Text.size(fx_symbol) == 3);
        assert (page_size > 0 and page_size <= 100);
        let filter = Text.toUppercase(fx_symbol);
        let ok = Map.filterDesc(
            currencyStore,
            thash,
            func(k : Text, yo : SupdTypes.CurrencyQuote) : Bool {
                yo.name == filter;
            },
        );
        let filteredQuoteHistory = Map.vals(ok);
        let result : [SupdTypes.CurrencyQuote] = Iter.toArray(filteredQuoteHistory);
        let top10_result = List.take(List.fromArray(result), page_size);
        let a = List.toArray(top10_result);
        return ?a;
    };

    //get most recent fx quote ttl FX_CACHE_TIME_SECONDS
    private func getQuoteCached(fx_symbol : Text) : ?SupdTypes.CurrencyQuote {
        assert (Text.size(fx_symbol) == 3);
        let filter = Text.toUppercase(fx_symbol);
        let ok = Map.filterDesc(
            currencyStore,
            thash,
            func(k : Text, yo : SupdTypes.CurrencyQuote) : Bool {
                Text.toUppercase(yo.name) == filter;
            },
        );
        if (Map.size(ok) > 0) {
            let most_recent = Iter.toArray(Map.vals(ok))[0];
            switch (?most_recent) {
                case null return null;
                case (?most_recent) {
                    let now = Nat64.toNat(Utils.now_seconds());
                    let cached_ts = Nat64.toNat(most_recent.created_at);
                    let diff = Nat.sub(now, cached_ts);
                    //Debug.print("DIFFERENCE: " # debug_show(diff));
                    if (diff > FX_CACHE_TIME_SECONDS) {
                        Debug.print("CACHE KEY: " # debug_show (filter));
                        return null;
                    };
                    //Debug.print("SERVING YOU FROM currencyStore CACHE for key: " # debug_show(filter));
                    return ?most_recent;
                };
            };
        };
        return null;
    };

    //get token with most recent price from cache FX_CACHE_TIME_SECONDS
    private func getTokenQuoteCached(token : Text) : ?SupdTypes.TokenQuote {
        let filter = Text.toUppercase(token);
        let ok = Map.filterDesc(
            quoteStore,
            thash,
            func(k : Text, yo : SupdTypes.TokenQuote) : Bool {
                Text.toUppercase(yo.name) == filter;
            },
        );
        if (Map.size(ok) > 0) {
            let most_recent = Iter.toArray(Map.vals(ok))[0];
            switch (?most_recent) {
                case null return null;
                case (?most_recent) {
                    let now = Nat64.toNat(Utils.now_seconds());
                    let cached_ts = Nat64.toNat(most_recent.created_at);
                    let diff = Nat.sub(now, cached_ts);
                    if (diff > FX_CACHE_TIME_SECONDS) {
                        return null;
                    };
                    //Debug.print("SERVING YOU FROM quoteStore CACHE for key: " # debug_show(filter));
                    return ?most_recent;
                };
            };
        };
        return null;
    };

    /* ------------------- CANISTERGEEK ----------------------- */
    public query ({ caller }) func getCanisterMetrics(parameters : Canistergeek.GetMetricsParameters) : async ?Canistergeek.CanisterMetrics {
        validateCaller(caller);
        canistergeekMonitor.getMetrics(parameters);
    };

    public shared ({ caller }) func collectCanisterMetrics() : async () {
        validateCaller(caller);
        canistergeekMonitor.collectMetrics();
    };

    public query ({ caller }) func getCanisterLog(request : ?Canistergeek.CanisterLogRequest) : async ?Canistergeek.CanisterLogResponse {
        validateCaller(caller);
        return canistergeekLogger.getLog(request);
    };

    private func validateCaller(principal : Principal) : () {
        //data is available only for specific principal
        if (not (Principal.toText(principal) == adminPrincipal)) {
            Prelude.unreachable();
        };
    };
};

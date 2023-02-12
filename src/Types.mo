module Types {
    //add new currency here and update FXFactory
    public type Currency = {
        #usd;
        #eur;
        #cad;
        #gbp;
        #chf;
        #idr;
        #jpy
    };

    //add new chain here and update TokenFactory
    public type TokenChain = {
        #btc_mainnet;
        #icp_mainnet;
        #icp_testnet;
        #eth_mainnet;
        #eth_testnet;
        #sol_mainnet;

        #tao_mainnet;
        #op_mainnet;
        #arb_mainnet;
        #base_mainnet;
        #ftm_mainnet;
        #bsc_mainnet;
    };

    //add new token here and update TokenFactory
    public type TokenCurrency = {
        #icp;
        #eth;
        #btc;
        #sol;
        #weth;
        #usdt;
        #usdc;
        #dai;
        #ckbtc;
        #cketh;
        #wbtc;
        #wtao;
        #exe; //memes for testing
        #sneed;
        #bonk;
        #test; //qa
    };

    //add new service here and update PriceFactory with your implementation
    public type PriceService = {
        #icpservice; 
        #coingecko; 
        #chainlink; 
        #coinmarketcap; 
        #kraken; 
        #testnet;
    };

    public type CurrencyQuote = {
        name : Text; //USD, EUR
        symbol : Text; //$, €, £
        value : Float; //0.75
        value_str : Text; //0.75
        created_at : Nat64;
        source : ?Text;
        currency_type : Currency;
        description : ?Text;
    };

    public type TokenQuote = {
        name : Text;
        symbol : Text;
        value : Float;
        value_str : Text;
        created_at : Nat64;
        source : ?Text;
        currency_type : Currency;
        token_type : TokenCurrency;
    };

    public type Token = {
        name : Text;
        decimals : Nat;
        contract : Text;
        created_at : Nat64;
        abi : Text;
        chains : [TokenChain];
        token_type : TokenCurrency;
        last_quote : ?TokenQuote;
        description : Text;
        slug : Text;
    };

    public type Response<T> = {
        status : Nat16;
        status_text : Text;
        data : ?T;
        error_text : ?Text;
    };
};

use starknet::ContractAddress;


#[starknet::interface]
trait ISwap<T> {
    fn swap(
        ref self: T, first_token: ContractAddress, second_token: ContractAddress, amount: u256
    ) -> bool;
    fn get_mtnTokenBalance(self: @T, mtnToken: ContractAddress) -> u256;
    fn get_AmountResultToken(self: @T, amount: u256, first_token: ContractAddress, second_token: ContractAddress ) -> u256;
    fn get_artTokenBalance(self: @T, artToken: ContractAddress) -> u256;
}

#[starknet::contract]
pub mod swap {
    use contracts::erc20::{
        erc20, IERC20Dispatcher, IERC20SafeDispatcher, IERC20DispatcherTrait,
        IERC20SafeDispatcherTrait
    };
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry, Map,
        StorageMapReadAccess, StorageMapWriteAccess
    };
    use starknet::{get_caller_address, get_contract_address, ContractAddress};

    use contracts::constants::{TOKEN_TOTAL_RESERVE_LIMIT};
    use contracts::{Errors};

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        SwapSuccessful: SwapSuccessful,
        SwapFailed: SwapFailed,
        PoolUpdated: PoolUpdated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SwapSuccessful {
        #[key]
        pub caller: ContractAddress,
        #[key]
        pub token_in: ContractAddress,
        #[key]
        pub token_out: ContractAddress,
        pub amount_in: u256,
        pub amount_out: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct SwapFailed {
        caller: ContractAddress,
        token_in: ContractAddress,
        token_out: ContractAddress,
        amount: u256,
        reason: felt252,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PoolUpdated {
        #[key]
        pub token_in: ContractAddress,
        #[key]
        pub token_out: ContractAddress,
        new_balance_token_in: u256,
        new_balance_token_out: u256,
    }

    #[storage]
    struct Storage {
        poolBalance: Map<ContractAddress, u256>,
        mtnToken: ContractAddress,
        artToken: ContractAddress,
        owner: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        mtnToken: ContractAddress,
        artToken: ContractAddress,
        owner: ContractAddress
    ) {
        self.poolBalance.entry(mtnToken).write(2000);
        self.poolBalance.entry(artToken).write(2000);
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl swapImpl of super::ISwap<ContractState> {
        fn swap(
            ref self: ContractState,
            first_token: ContractAddress,
            second_token: ContractAddress,
            amount: u256
        ) -> bool {
            let caller = get_caller_address();
            let my_contract_address = get_contract_address();

            let second_token_instance = IERC20Dispatcher { contract_address: second_token };
            let first_token_instance = IERC20Dispatcher { contract_address: first_token };

            let contract_first_token_total_supply = first_token_instance.get_total_supply();

            let contract_second_token_total_supply = second_token_instance.get_total_supply();

            assert(
                contract_first_token_total_supply.try_into().unwrap() != 0, Errors::INVALID_TOKEN
            );
            assert(
                contract_second_token_total_supply.try_into().unwrap() != 0, Errors::INVALID_TOKEN
            );

            //Validation
            assert(!self.is_zero_address(first_token), Errors::ZERO_ADDRESS);
            assert(!self.is_zero_address(second_token), Errors::ZERO_ADDRESS);
            assert(first_token != second_token, Errors::SAME_TOKEN);
            assert(amount > 0, Errors::ZERO_AMOUNT);
            assert(amount < TOKEN_TOTAL_RESERVE_LIMIT, Errors::EXCEEDS_RESERVE_LIMIT);

            let contract_first_token_allowance = first_token_instance
                .allowance(caller, my_contract_address);

            assert(
                contract_first_token_allowance.try_into().unwrap() > amount,
                Errors::LIMITED_ALLOWANCE
            );

            let firsttokenpoolbal = self.poolBalance.entry(first_token).read();
            let secondtokenpoolbal = self.poolBalance.entry(second_token).read();

            let result_token = (secondtokenpoolbal * amount) / (firsttokenpoolbal + amount);

            // Check DEX Contract Token Balance for Swap Execution
            let contract_second_token_balance = second_token_instance
                .balance_of(my_contract_address);
            assert(
                contract_second_token_balance.try_into().unwrap() > result_token,
                Errors::INSUFFICIENT_TOKEN
            );

            first_token_instance
                .transfer_from(caller, my_contract_address, amount.try_into().unwrap());
            second_token_instance.transfer(caller, result_token.try_into().unwrap());

            self
                .emit(
                    Event::SwapSuccessful(
                        SwapSuccessful {
                            caller,
                            token_in: first_token,
                            token_out: second_token,
                            amount_in: amount,
                            amount_out: result_token
                        }
                    )
                );

            self
                .emit(
                    Event::PoolUpdated(
                        PoolUpdated {
                            token_in: first_token,
                            token_out: second_token,
                            new_balance_token_in: self.poolBalance.read(first_token),
                            new_balance_token_out: self.poolBalance.read(second_token),
                        }
                    )
                );
            true
        }

        fn get_mtnTokenBalance(self: @ContractState, mtnToken: ContractAddress) -> u256 {
            self.poolBalance.entry(mtnToken).read()
        }

        fn get_artTokenBalance(self: @ContractState, artToken: ContractAddress) -> u256 {
            self.poolBalance.entry(artToken).read()
        }


        fn get_AmountResultToken(self: @ContractState, amount: u256, first_token: ContractAddress, second_token: ContractAddress) -> u256 {
            let firsttokenpoolbal = self.poolBalance.read(first_token);

            let secondtokenpoolbal = self.poolBalance.read(second_token);

            let result_token = (secondtokenpoolbal * amount) / (firsttokenpoolbal + amount);
            result_token
        }

    }

    #[generate_trait]
    impl Private of PrivateTrait {
        fn only_owner(self: @ContractState) {
            let caller = get_caller_address();
            let owner = self.owner.read();
            assert(caller == owner, Errors::UNAUTHORIZED);
        }

        fn is_zero_address(self: @ContractState, account: ContractAddress) -> bool {
            account.is_zero()
        }
    }
}

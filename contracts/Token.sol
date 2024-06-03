// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

contract Token is ERC20, Ownable {
    using SafeERC20 for IERC20;
    /*//////////////////////////////////////////////////////////////
                            TAX VARIABLES
    //////////////////////////////////////////////////////////////*/
    struct WalletState {
        bool isMarketPair;
        bool isExemptFromTax;
    }
    // Saves gas!
    mapping(address => WalletState) public walletStates;

    // Set to 10/10 when trading is open. SetTaxes can only set it
    // up to 10/10.

    uint8 public sellTax = 10;

    // When set is true, tax will no longer be change-able.
    bool private _isTaxEnabled = true;

    /*//////////////////////////////////////////////////////////////
                            CONTRACT SWAP
    //////////////////////////////////////////////////////////////*/

    // Once switched on, can never be switched off.
    bool public isTradingOpen = false;

    bool private _inSwap = false;

    /*//////////////////////////////////////////////////////////////
                            UNISWAP
    //////////////////////////////////////////////////////////////*/

    IUniswapV2Router02 public uniswapV2Router;

    /*//////////////////////////////////////////////////////////////
                            TAX RECIPIENTS
    //////////////////////////////////////////////////////////////*/

    // Platform cut will be sent to this address.
    // Defaults to contract creator.
    address public protocolAddress;

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event ExcludedFromFeesUpdated(address wallet, bool isExcluded);
    event MarketPairUpdated(address pair, bool isMarketPair);

    event ProtocolAddressUpdated(address newProtocolAddress);

    event TradingOpen();

    /*//////////////////////////////////////////////////////////////
                            MAIN LOGIC
    //////////////////////////////////////////////////////////////*/

    constructor() ERC20("Token", "TKN") Ownable(msg.sender) {
        super._update(address(0), msg.sender, (1_000_000_000 * 10 ** 18));

        address uniswapV2Router02Address = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            uniswapV2Router02Address
        );

        // Create the pair and mark it as a market pair to enable taxes.
        address uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        uniswapV2Router = _uniswapV2Router;
        _approve(address(this), uniswapV2Router02Address, type(uint256).max);
        setMarketPair(uniswapV2Pair, true);

        protocolAddress = msg.sender;

        // Exclude owner, this contract and Uniswap router from fees.
        walletStates[msg.sender] = WalletState({
            isMarketPair: false,
            isExemptFromTax: true
        });
        emit ExcludedFromFeesUpdated(msg.sender, true);
        walletStates[address(this)] = WalletState({
            isMarketPair: false,
            isExemptFromTax: true
        });

        emit ExcludedFromFeesUpdated(address(this), true);
        walletStates[uniswapV2Router02Address] = WalletState({
            isMarketPair: false,
            isExemptFromTax: true
        });
        emit ExcludedFromFeesUpdated(uniswapV2Router02Address, true);
    }

    receive() external payable {}

    /// @notice Returns if an address is excluded from tax.
    function isTaxExempt(address account_) external view returns (bool) {
        return walletStates[account_].isExemptFromTax;
    }

    /// @notice Returns if the tax is enabled or not. Tax only exists on market pairs.
    function isTaxEnabled() external view returns (bool) {
        return _isTaxEnabled;
    }

    /// @notice _update function overrides the _update function from the perent contract and contains logic for tax and tax distribution
    /// @dev this override function will be called from the top level transfer and transferFrom function whenever user initates transfer or buy and sell happens
    /// @dev this function breaks _mint. Use super._update instead.
    /// @param from address from the amount will be transfered
    /// @param to address to where the amount will be transfered
    /// @param amount number of tokens to transfer
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override {
        // Parent ERC20 already checks that from/to are not zero address.

        uint256 fromBalance = balanceOf(from);
        require(
            fromBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );

        WalletState memory fromState = walletStates[from];
        WalletState memory toState = walletStates[to];

        bool isTaxExempt_ = (fromState.isExemptFromTax ||
            toState.isExemptFromTax);

        uint256 taxAmount;

        if (fromState.isMarketPair || toState.isMarketPair) {
            require(
                isTradingOpen || msg.sender == owner() || tx.origin == owner(),
                "Token: Trading not open yet"
            );
        }

        if (toState.isMarketPair && isTaxExempt_ == false && _isTaxEnabled) {
            taxAmount = (amount * sellTax) / 100;
        } else {
            taxAmount = 0;
        }

        if (taxAmount != 0 && _inSwap == false) {
            super._update(from, to, amount - taxAmount);
            super._update(from, address(this), taxAmount);
        } else {
            super._update(from, to, amount);
        }
    }

    modifier lockTheSwap() {
        _inSwap = true;
        _;
        _inSwap = false;
    }

    /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Opens the trading, enabling taxes. Can only be called once.
    function openTrading() external onlyOwner {
        require(isTradingOpen == false, "Trading already open");

        isTradingOpen = true;
        sellTax = 10;

        emit TradingOpen();
    }

    /// @notice Sets an address's tax exempt status.
    function setTaxExempt(address account, bool isExempt) external onlyOwner {
        require(account != address(this), "Can't change contract");
        WalletState memory state = walletStates[account];
        state.isExemptFromTax = isExempt;
        walletStates[account] = state;
        emit ExcludedFromFeesUpdated(account, isExempt);
    }

    /// @notice Set the receiver of platform taxes.
    function setTaxAddress(address newProtocolAddress_) external onlyOwner {
        protocolAddress = newProtocolAddress_;
        emit ProtocolAddressUpdated(newProtocolAddress_);
    }

    function setMarketPair(address account, bool value) public onlyOwner {
        require(account != address(this), "cant change contract");
        WalletState memory state = walletStates[account];
        state.isMarketPair = value;
        walletStates[account] = state;
        emit MarketPairUpdated(account, value);
    }
}

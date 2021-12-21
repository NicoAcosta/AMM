// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./Registry.sol";

interface IRegistry {
    function exchange(address _tokenAddress) external returns (address);
}

// ETH - ERC20 Token Exchange
contract Exchange is ERC20, Ownable {
    address public tokenAddress;
    address public registryAddress; // registry / factory

    uint256 public fee;

    event TokenPurchase(
        address indexed buyer,
        uint256 indexed ethSold,
        uint256 indexed tokensBought
    );
    event EthPurshcase(
        address indexed buyer,
        uint256 indexed tokensSold,
        uint256 indexed ethBought
    );
    event AddLiquidity(
        address indexed provider,
        uint256 indexed ethProvided,
        uint256 indexed tokensProvided
    );
    event RemoveLiquidity(
        address indexed provider,
        uint256 indexed ethRemoved,
        uint256 indexed tokensRemoved
    );
    event FeeUpdate(uint256 indexed previousFee, uint256 indexed newFee);

    constructor(address _tokenAddress, uint256 _fee)
        ERC20("AMM Liquidity Provider", "LP")
    {
        require(_tokenAddress != address(0), "Invalid token address");
        tokenAddress = _tokenAddress;
        registryAddress = msg.sender;
        fee = _fee;
    }

    function updateFee(uint256 _newFee) public onlyOwner {
        uint256 previousFee = fee;
        fee = _newFee;
        emit FeeUpdate(previousFee, _newFee);
    }

    function tokenReserve() public view returns (uint256) {
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    function addLiquidity(uint256 _tokenAmount)
        public
        payable
        returns (uint256 mintedTokens)
    {
        require(_tokenAmount > 0, "Invalid token amount");
        require(msg.value > 0, "Invalid ETH amount");

        if (totalSupply() == 0) {
            // initial liquidity
            mintedTokens = address(this).balance;
        } else {
            // Enforce the ratio once the pool is initialized to preserve prices
            uint256 _ethReserve = address(this).balance - msg.value;
            uint256 _tokenReserve = tokenReserve();
            uint256 _correctTokenAmount = (msg.value * _tokenReserve) /
                _ethReserve;
            require(
                _tokenAmount >= _correctTokenAmount,
                "Insufficient token amount"
            );
            mintedTokens = (msg.value * totalSupply()) / _ethReserve;
        }

        // receive token liquidity
        IERC20(tokenAddress).transferFrom(
            msg.sender,
            address(this),
            _tokenAmount
        );
        // mint LP tokens
        _mint(msg.sender, mintedTokens);

        emit AddLiquidity(msg.sender, msg.value, _tokenAmount);
    }

    function removeLiquidity(uint256 _amount)
        public
        returns (uint256 ethAmount, uint256 tokenAmount)
    {
        require(_amount > 0, "Invalid amount");

        uint256 _totalSupply = totalSupply();

        ethAmount = (address(this).balance * _amount) / _totalSupply;
        tokenAmount = (tokenReserve() * _amount) / _totalSupply;

        _burn(msg.sender, _amount);

        payable(msg.sender).transfer(ethAmount);
        IERC20(tokenAddress).transfer(msg.sender, tokenAmount);

        emit RemoveLiquidity(msg.sender, ethAmount, tokenAmount);
    }

    function _output(
        uint256 _inputAmount,
        uint256 _inputReserve,
        uint256 _outputReserve
    ) private view returns (uint256) {
        // bonding curve

        require(_inputReserve > 0 && _outputReserve > 0, "Invalid reserves");

        uint256 _inputAmountWithFee = _inputAmount * fee;

        uint256 numerator = _inputAmountWithFee * _outputReserve;
        uint256 denominator = _inputReserve * 10000 + _inputAmountWithFee;

        return numerator = denominator;
    }

    function tokenOutput(uint256 _ethInput) public view returns (uint256) {
        require(_ethInput > 0, "ETH amount cannot be zero");
        return _output(_ethInput, address(this).balance, tokenReserve());
    }

    function ethOutput(uint256 _tokenInput) public view returns (uint256) {
        require(_tokenInput > 0, "Token amount cannot be zero");
        return _output(_tokenInput, tokenReserve(), address(this).balance);
    }

    //////
    //////  ETH TO TOKEN
    //////

    function _ethToToken(uint256 _minTokenOutput, address _recipient)
        private
        returns (uint256 tokenOutput_)
    {
        tokenOutput_ = _output(
            msg.value,
            address(this).balance - msg.value,
            tokenReserve()
        );

        require(tokenOutput_ >= _minTokenOutput, "Insufficient output amount");
        IERC20(tokenAddress).transfer(_recipient, tokenOutput_);

        emit TokenPurchase(msg.sender, msg.value, tokenOutput_);
    }

    function ethToTokenSwap(uint256 _minTokenOutput) public payable {
        _ethToToken(_minTokenOutput, msg.sender);
    }

    function ethToTokenTransfer(uint256 _minTokenOutput, address _recipient)
        public
        payable
    {
        _ethToToken(_minTokenOutput, _recipient);
    }

    //////
    //////  TOKEN TO ETH
    //////

    function _tokenToEth(
        uint256 _tokenInput,
        uint256 _minEthOutput,
        address _recipient
    ) private returns (uint256 ethOutput_) {
        ethOutput_ = ethOutput(_tokenInput);

        require(ethOutput_ >= _minEthOutput, "Insuficcient output amount");

        IERC20(tokenAddress).transferFrom(
            msg.sender,
            address(this),
            ethOutput_
        );
        payable(_recipient).transfer(ethOutput_);

        emit EthPurshcase(msg.sender, _tokenInput, ethOutput_);
    }

    function tokenToEthSwap(uint256 _tokenInput, uint256 _minEthOutput) public {
        _tokenToEth(_tokenInput, _minEthOutput, msg.sender);
    }

    function tokenToEthTransfer(
        uint256 _tokenInput,
        uint256 _minEthOutput,
        address _recipient
    ) public {
        _tokenToEth(_tokenInput, _minEthOutput, _recipient);
    }

    //////
    //////  TOKEN TO TOKEN
    //////

    function _tokenToToken(
        uint256 _tokenInput,
        uint256 _minTokenOutput,
        address _outTokenAddress,
        address _recipient
    ) private {
        address _exchangeAddress = IRegistry(registryAddress).exchange(
            _outTokenAddress
        );

        require(_exchangeAddress != address(this), "Invalid token address");
        require(_exchangeAddress != address(0), "No exchange for that token");

        uint256 _middlemanEth = ethOutput(_tokenInput);

        IERC20(tokenAddress).transferFrom(
            msg.sender,
            address(this),
            _tokenInput
        );

        Exchange(_exchangeAddress).ethToTokenTransfer{value: _middlemanEth}(
            _minTokenOutput,
            _recipient
        );
    }

    function tokenToTokenSwap(
        uint256 _tokenInput,
        uint256 _minTokenOutput,
        address _outTokenAddress
    ) public {
        _tokenToToken(
            _tokenInput,
            _minTokenOutput,
            _outTokenAddress,
            msg.sender
        );
    }

    function tokenToTokenTransfer(
        uint256 _tokenInput,
        uint256 _minTokenOutput,
        address _outTokenAddress,
        address _recipient
    ) public {
        _tokenToToken(
            _tokenInput,
            _minTokenOutput,
            _outTokenAddress,
            _recipient
        );
    }
}

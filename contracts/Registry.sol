// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./Exchange.sol";

// Exchanges Registry / Factory
contract Registry {
    mapping(address => address) public tokenToExchange;

    event NewExchange(address indexed token, address indexed exchange);

    function createExchange(address _tokenAddress)
        external
        returns (address exchangeAddress)
    {
        require(_tokenAddress != address(0), "Invalid token address");
        require(
            tokenToExchange[_tokenAddress] == address(0),
            "Exchange already exists"
        );

        Exchange _exchange = new Exchange(_tokenAddress);
        exchangeAddress = address(_exchange);

        tokenToExchange[_tokenAddress] = exchangeAddress;

        emit NewExchange(_tokenAddress, exchangeAddress);
    }

    function exchange(address _tokenAddress) external view returns (address) {
        return tokenToExchange[_tokenAddress];
    }
}

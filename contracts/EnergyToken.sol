// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title EnergyToken
 * @dev ERC-20 token representing solar energy credits
 *      1 token = 1 kWh of solar energy
 *
 * Flow:
 *  1. Seller lists energy  → platform calls mintEnergy()   → seller receives SEC tokens
 *  2. Buyer purchases      → platform calls recordPurchase() → tokens move seller → buyer
 *  3. Buyer uses energy    → buyer calls consumeEnergy()    → tokens are burned (destroyed)
 */
contract EnergyToken is ERC20, ERC20Burnable, Ownable {

    // ─── Events ─────────────────────────────────────────────────────────────
    event EnergyMinted(address indexed seller, uint256 amountKwh, string metadata);
    event EnergyPurchased(address indexed buyer, address indexed seller, uint256 amountKwh, uint256 priceWei);
    event EnergyConsumed(address indexed consumer, uint256 amountKwh);

    // ─── State ───────────────────────────────────────────────────────────────
    mapping(address => uint256) public totalEnergyProduced;   // kWh produced per seller
    mapping(address => uint256) public totalEnergyConsumed;   // kWh consumed per buyer

    // ─── Constructor ─────────────────────────────────────────────────────────
    constructor(address initialOwner)
        ERC20("Solar Energy Credit", "SEC")
        Ownable(initialOwner)
    {}

    // ─── Owner-only functions (called by FastAPI backend) ────────────────────

    /**
     * @dev Mint tokens when a seller creates a listing.
     *      Only the platform (owner) can call this.
     * @param to         Seller wallet address
     * @param amountKwh  Energy amount in kWh
     * @param metadata   Extra info e.g. listing ID from DB
     */
    function mintEnergy(
        address to,
        uint256 amountKwh,
        string memory metadata
    ) public onlyOwner {
        require(to != address(0), "Cannot mint to zero address");
        require(amountKwh > 0, "Amount must be greater than zero");

        uint256 tokenAmount = amountKwh * 10 ** decimals();
        _mint(to, tokenAmount);

        totalEnergyProduced[to] += amountKwh;
        emit EnergyMinted(to, amountKwh, metadata);
    }

    /**
     * @dev Transfer tokens from seller to buyer after purchase confirmed in DB.
     *      Only the platform (owner) can call this.
     * @param seller     Seller wallet address
     * @param buyer      Buyer wallet address
     * @param amountKwh  Energy purchased in kWh
     * @param priceWei   Price paid in wei
     */
    function recordPurchase(
        address seller,
        address buyer,
        uint256 amountKwh,
        uint256 priceWei
    ) public onlyOwner {
        require(seller != address(0), "Invalid seller address");
        require(buyer != address(0), "Invalid buyer address");
        require(amountKwh > 0, "Amount must be greater than zero");

        uint256 tokenAmount = amountKwh * 10 ** decimals();
        _transfer(seller, buyer, tokenAmount);

        emit EnergyPurchased(buyer, seller, amountKwh, priceWei);
    }

    // ─── Public functions (called by buyers) ─────────────────────────────────

    /**
     * @dev Burn tokens when buyer actually consumes the energy.
     * @param amountKwh  Energy consumed in kWh
     */
    function consumeEnergy(uint256 amountKwh) public {
        require(amountKwh > 0, "Amount must be greater than zero");

        uint256 tokenAmount = amountKwh * 10 ** decimals();
        burn(tokenAmount);

        totalEnergyConsumed[msg.sender] += amountKwh;
        emit EnergyConsumed(msg.sender, amountKwh);
    }

    // ─── View functions ───────────────────────────────────────────────────────

    /**
     * @dev Get balance in kWh (readable — no 18 decimals confusion)
     */
    function getEnergyBalance(address account) public view returns (uint256) {
        return balanceOf(account) / 10 ** decimals();
    }

    /**
     * @dev Total kWh ever produced by a seller
     */
    function getEnergyProduced(address seller) public view returns (uint256) {
        return totalEnergyProduced[seller];
    }

    /**
     * @dev Total kWh ever consumed by a buyer
     */
    function getEnergyConsumed(address buyer) public view returns (uint256) {
        return totalEnergyConsumed[buyer];
    }
}


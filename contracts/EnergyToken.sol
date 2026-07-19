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
    event EnergyMinted(address indexed seller, uint256 amountKwh, uint256 pricePerKwh, string listingId);
    event EnergyPurchased(address indexed buyer, address indexed seller, uint256 amountKwh, uint256 priceWei);
    event EnergyConsumed(address indexed consumer, uint256 amountKwh);
    event ListingSnapshotStored(string indexed listingId, bytes32 snapshotHash, uint256 originalEnergyKwh);

    // ─── State ───────────────────────────────────────────────────────────────
    mapping(address => uint256) public totalEnergyProduced;   // kWh produced per seller
    mapping(address => uint256) public totalEnergyConsumed;   // kWh consumed per buyer

    // Listing integrity: listingId (DB UUID string) => on-chain snapshot
    struct ListingRecord {
        address seller;
        uint256 originalEnergyKwh;  // IMMUTABLE original energy (stored at creation)
        uint256 pricePerKwh;   // stored as micro-units (price * 1e6) to avoid floats
        bytes32 listingHash;   // SHA256 of IMMUTABLE fields — tamper detection
        bool    exists;
    }
    mapping(string => ListingRecord) public listingRecords;  // listingId => record

    // Purchase tracking for energy tampering detection
    // listingId => array of purchase amounts (kWh)
    struct Purchase {
        address buyer;
        uint256 amountKwh;
        uint256 timestamp;
    }
    mapping(string => Purchase[]) public listingPurchases;  // Track all purchases per listing
    
    // Snapshot metadata: listingId => immutable snapshot details
    struct ListingSnapshot {
        uint256 originalEnergyKwh;
        bytes32 snapshotHash;
        uint256 createdAt;
        bool    verified;
    }
    mapping(string => ListingSnapshot) public listingSnapshots;

    // ─── Constructor ─────────────────────────────────────────────────────────
    constructor(address initialOwner)
        ERC20("Solar Energy Credit", "SEC")
        Ownable(initialOwner)
    {}

    // ─── Owner-only functions (called by FastAPI backend) ────────────────────

    /**
     * @dev Mint tokens when a seller creates a listing.
     *      Only the platform (owner) can call this.
     * @param to              Seller wallet address
     * @param amountKwh       Original energy amount in kWh (IMMUTABLE)
     * @param pricePerKwh     Price per kWh in micro-units (price_per_kwh * 1e6), e.g. 1.5 => 1500000
     * @param listingId       DB listing UUID — used to verify listing integrity later
     * @param listingHash     SHA256 hash of IMMUTABLE fields (price, title, location, etc.)
     */
    function mintEnergy(
        address to,
        uint256 amountKwh,
        uint256 pricePerKwh,
        string memory listingId,
        bytes32 listingHash
    ) public onlyOwner {
        require(to != address(0), "Cannot mint to zero address");
        require(amountKwh > 0, "Amount must be greater than zero");
        require(pricePerKwh > 0, "Price must be greater than zero");

        uint256 tokenAmount = amountKwh * 10 ** decimals();
        _mint(to, tokenAmount);

        totalEnergyProduced[to] += amountKwh;

        // Store IMMUTABLE listing snapshot on-chain
        listingRecords[listingId] = ListingRecord({
            seller:               to,
            originalEnergyKwh:    amountKwh,  // IMMUTABLE original energy
            pricePerKwh:          pricePerKwh,
            listingHash:          listingHash,
            exists:               true
        });

        // Store snapshot metadata for verification
        listingSnapshots[listingId] = ListingSnapshot({
            originalEnergyKwh: amountKwh,
            snapshotHash:      listingHash,
            createdAt:         block.timestamp,
            verified:          true
        });

        emit EnergyMinted(to, amountKwh, pricePerKwh, listingId);
        emit ListingSnapshotStored(listingId, listingHash, amountKwh);
    }

    /**
     * @dev Retrieve the on-chain snapshot of a listing for tamper detection.
     *      Returns the IMMUTABLE original energy that was stored at creation.
     */
    function getListingRecord(string memory listingId)
        public view
        returns (address seller, uint256 originalEnergyKwh, uint256 pricePerKwh, bytes32 listingHash, bool exists)
    {
        ListingRecord memory r = listingRecords[listingId];
        return (r.seller, r.originalEnergyKwh, r.pricePerKwh, r.listingHash, r.exists);
    }

    /**
     * @dev Transfer tokens from seller to buyer after purchase confirmed in DB.
     *      Only the platform (owner) can call this.
     *      Also records the purchase on-chain for energy verification.
     * @param seller     Seller wallet address
     * @param buyer      Buyer wallet address
     * @param amountKwh  Energy purchased in kWh
     * @param priceWei   Price paid in wei
     * @param listingId  DB listing UUID — used to track purchase for this listing
     */
    function recordPurchase(
        address seller,
        address buyer,
        uint256 amountKwh,
        uint256 priceWei,
        string memory listingId
    ) public onlyOwner {
        require(seller != address(0), "Invalid seller address");
        require(buyer != address(0), "Invalid buyer address");
        require(amountKwh > 0, "Amount must be greater than zero");

        uint256 tokenAmount = amountKwh * 10 ** decimals();
        _transfer(seller, buyer, tokenAmount);

        // Record purchase for this listing (immutable on-chain)
        listingPurchases[listingId].push(Purchase({
            buyer: buyer,
            amountKwh: amountKwh,
            timestamp: block.timestamp
        }));

        emit EnergyPurchased(buyer, seller, amountKwh, priceWei);
    }

    // ─── Public functions (called by buyers) ─────────────────────────────────

    /**
     * @dev Burn tokens when buyer actually consumes the energy.
     *      NOTE: NOT used in the current project.
     *      This requires the buyer to sign the transaction themselves
     *      (i.e., buyer's private key must be available in the caller).
     *      Since the FastAPI backend does NOT store user private keys,
     *      we use consumeEnergyFor() (onlyOwner) instead — backend signs
     *      on behalf of the buyer using Account #0's private key.
     *      Kept here for reference if a frontend wallet (e.g. MetaMask) is added later.
     */
    /**
     * @dev Burn tokens directly by the token holder (buyer consuming energy)
     * @param amountKwh Energy consumed in kWh
     */
    function consumeEnergy(uint256 amountKwh) public {
        require(amountKwh > 0, "Amount must be greater than zero");

        uint256 tokenAmount = amountKwh * 10 ** decimals();
        burn(tokenAmount);

        totalEnergyConsumed[msg.sender] += amountKwh;
        emit EnergyConsumed(msg.sender, amountKwh);
    }

    /**
     * @dev Burn tokens on behalf of a buyer — called by platform backend (owner).
     *      Used when buyer triggers "consume energy" via the API
     *      and the backend holds the signing key.
     * @param buyer      Buyer wallet address
     * @param amountKwh  Energy consumed in kWh
     */
    function consumeEnergyFor(address buyer, uint256 amountKwh) public onlyOwner {
        require(buyer != address(0), "Invalid buyer address");
        require(amountKwh > 0, "Amount must be greater than zero");

        uint256 tokenAmount = amountKwh * 10 ** decimals();
        _burn(buyer, tokenAmount);

        totalEnergyConsumed[buyer] += amountKwh;
        emit EnergyConsumed(buyer, amountKwh);
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

    // ─── Energy Tampering Detection Functions ───────────────────────────────

    /**
     * @dev Get total energy purchased for a listing.
     *      Used to verify: remaining = original - purchases
     * @param listingId DB listing UUID
     */
    function getTotalPurchasedEnergy(string memory listingId) public view returns (uint256) {
        Purchase[] memory purchases = listingPurchases[listingId];
        uint256 total = 0;
        for (uint256 i = 0; i < purchases.length; i++) {
            total += purchases[i].amountKwh;
        }
        return total;
    }

    /**
     * @dev Get all purchases for a listing.
     * @param listingId DB listing UUID
     */
    function getListingPurchases(string memory listingId)
        public view
        returns (Purchase[] memory)
    {
        return listingPurchases[listingId];
    }

    /**
     * @dev Verify listing energy integrity.
     *      
     *      Formula: remaining_energy = original_energy - total_purchases
     *      
     *      Returns:
     *        - original: Energy amount at listing creation (immutable)
     *        - totalPurchased: Sum of all purchases for this listing
     *        - expectedRemaining: What energy_kwh SHOULD be in DB
     *        - purchaseCount: Number of purchase transactions
     *
     * @param listingId DB listing UUID
     */
    function verifyListingEnergy(string memory listingId)
        public view
        returns (
            uint256 original,
            uint256 totalPurchased,
            uint256 expectedRemaining,
            uint256 purchaseCount
        )
    {
        ListingRecord memory record = listingRecords[listingId];
        require(record.exists, "Listing not found");

        uint256 total = getTotalPurchasedEnergy(listingId);
        uint256 expected = record.originalEnergyKwh > total 
            ? record.originalEnergyKwh - total 
            : 0;

        return (
            record.originalEnergyKwh,
            total,
            expected,
            listingPurchases[listingId].length
        );
    }

    /**
     * @dev Check if listing energy matches blockchain records.
     *      Backend calls this to detect tampering.
     *      
     *      Attack Detection:
     *        ✓ Energy restored after purchase
     *        ✓ Energy fraudulently increased
     *        ✓ Energy fraudulently decreased beyond purchases
     *      
     * @param listingId DB listing UUID
     * @param currentEnergyKwh Energy amount reported in DB
     */
    function isEnergyTampered(string memory listingId, uint256 currentEnergyKwh)
        public view
        returns (bool tampered, string memory reason)
    {
        ListingRecord memory record = listingRecords[listingId];
        require(record.exists, "Listing not found");

        uint256 totalPurchased = getTotalPurchasedEnergy(listingId);
        uint256 expectedRemaining = record.originalEnergyKwh > totalPurchased
            ? record.originalEnergyKwh - totalPurchased
            : 0;

        // Check if current energy matches expected
        if (currentEnergyKwh != expectedRemaining) {
            return (
                true,
                string(
                    abi.encodePacked(
                        "Energy mismatch: expected ",
                        _uint2str(expectedRemaining),
                        " kWh, got ",
                        _uint2str(currentEnergyKwh),
                        " kWh"
                    )
                )
            );
        }

        return (false, "Energy verified OK");
    }

    /**
     * @dev Get snapshot metadata for a listing.
     */
    function getListingSnapshot(string memory listingId)
        public view
        returns (uint256 originalEnergyKwh, bytes32 snapshotHash, uint256 createdAt, bool verified)
    {
        ListingSnapshot memory snap = listingSnapshots[listingId];
        return (snap.originalEnergyKwh, snap.snapshotHash, snap.createdAt, snap.verified);
    }

    // ─── Utility Functions ───────────────────────────────────────────────────

    /**
     * @dev Convert uint to string for error messages
     */
    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}


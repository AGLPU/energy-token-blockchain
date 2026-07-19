const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("EnergyToken", function () {

  let energyToken;
  let owner;      // platform (contract owner)
  let seller;     // solar panel owner
  let buyer;      // energy buyer

  // Deploy a fresh contract before each test
  beforeEach(async function () {
    [owner, seller, buyer] = await ethers.getSigners();

    const EnergyToken = await ethers.getContractFactory("EnergyToken");
    energyToken = await EnergyToken.deploy(owner.address);
    await energyToken.waitForDeployment();
  });

  // ─── Deployment ────────────────────────────────────────────────────────────
  describe("Deployment", function () {
    it("Should have correct name and symbol", async function () {
      expect(await energyToken.name()).to.equal("Solar Energy Credit");
      expect(await energyToken.symbol()).to.equal("SEC");
    });

    it("Should set deployer as owner", async function () {
      expect(await energyToken.owner()).to.equal(owner.address);
    });

    it("Should start with zero total supply", async function () {
      expect(await energyToken.totalSupply()).to.equal(0);
    });
  });

  // ─── Minting ───────────────────────────────────────────────────────────────
  describe("mintEnergy", function () {
    it("Owner can mint energy tokens to a seller", async function () {
      const listingHash = ethers.id("listing-001");
      await energyToken.connect(owner).mintEnergy(
        seller.address,
        100,
        1500000,  // pricePerKwh in micro-units
        "listing-001",
        listingHash
      );

      // 100 kWh = 100 * 10^18 tokens
      const balance = await energyToken.balanceOf(seller.address);
      expect(balance).to.equal(ethers.parseUnits("100", 18));
    });

    it("getEnergyBalance returns kWh (human readable)", async function () {
      const listingHash = ethers.id("listing-002");
      await energyToken.connect(owner).mintEnergy(
        seller.address,
        50,
        1500000,
        "listing-002",
        listingHash
      );
      expect(await energyToken.getEnergyBalance(seller.address)).to.equal(50);
    });

    it("Tracks totalEnergyProduced per seller", async function () {
      const hash1 = ethers.id("listing-001");
      const hash2 = ethers.id("listing-002");
      
      await energyToken.connect(owner).mintEnergy(
        seller.address,
        100,
        1500000,
        "listing-001",
        hash1
      );
      await energyToken.connect(owner).mintEnergy(
        seller.address,
        50,
        1500000,
        "listing-002",
        hash2
      );
      expect(await energyToken.totalEnergyProduced(seller.address)).to.equal(150);
    });

    it("Emits EnergyMinted event", async function () {
      const listingHash = ethers.id("listing-001");
      await expect(
        energyToken.connect(owner).mintEnergy(
          seller.address,
          100,
          1500000,
          "listing-001",
          listingHash
        )
      ).to.emit(energyToken, "EnergyMinted")
        .withArgs(seller.address, 100, 1500000, "listing-001");
    });

    it("Non-owner cannot mint", async function () {
      const listingHash = ethers.id("listing-test");
      await expect(
        energyToken.connect(seller).mintEnergy(
          seller.address,
          100,
          1500000,
          "listing-test",
          listingHash
        )
      ).to.be.reverted;
    });

    it("Cannot mint zero amount", async function () {
      const listingHash = ethers.id("listing-test");
      await expect(
        energyToken.connect(owner).mintEnergy(
          seller.address,
          0,
          1500000,
          "listing-test",
          listingHash
        )
      ).to.be.revertedWith("Amount must be greater than zero");
    });
  });

  // ─── Purchase Recording ────────────────────────────────────────────────────
  describe("recordPurchase", function () {
    beforeEach(async function () {
      // Give seller 200 kWh first
      const setupHash = ethers.id("setup");
      await energyToken.connect(owner).mintEnergy(
        seller.address,
        200,
        1500000,
        "setup",
        setupHash
      );
    });

    it("Transfers tokens from seller to buyer", async function () {
      const priceWei = ethers.parseEther("0.1");
      await energyToken.connect(owner).recordPurchase(
        seller.address,
        buyer.address,
        100,
        priceWei,
        "setup"  // listingId
      );

      expect(await energyToken.getEnergyBalance(seller.address)).to.equal(100);
      expect(await energyToken.getEnergyBalance(buyer.address)).to.equal(100);
    });

    it("Emits EnergyPurchased event", async function () {
      const priceWei = ethers.parseEther("0.05");
      await expect(
        energyToken.connect(owner).recordPurchase(
          seller.address,
          buyer.address,
          50,
          priceWei,
          "setup"  // listingId
        )
      ).to.emit(energyToken, "EnergyPurchased")
        .withArgs(buyer.address, seller.address, 50, priceWei);
    });

    it("Non-owner cannot record purchase", async function () {
      await expect(
        energyToken.connect(buyer).recordPurchase(seller.address, buyer.address, 10, 0, "setup")
      ).to.be.reverted;
    });
  });

  // ─── Consume Energy ────────────────────────────────────────────────────────
  describe("consumeEnergy", function () {
    beforeEach(async function () {
      // Mint to seller, transfer to buyer
      const setupHash = ethers.id("setup");
      await energyToken.connect(owner).mintEnergy(
        seller.address,
        100,
        1500000,
        "setup",
        setupHash
      );
      await energyToken.connect(owner).recordPurchase(
        seller.address,
        buyer.address,
        100,
        0,
        "setup"  // listingId
      );
    });

    it("Buyer can burn (consume) tokens", async function () {
      await energyToken.connect(buyer).consumeEnergy(40);
      expect(await energyToken.getEnergyBalance(buyer.address)).to.equal(60);
    });

    it("Tracks totalEnergyConsumed", async function () {
      await energyToken.connect(buyer).consumeEnergy(40);
      expect(await energyToken.totalEnergyConsumed(buyer.address)).to.equal(40);
    });

    it("Emits EnergyConsumed event", async function () {
      await expect(
        energyToken.connect(buyer).consumeEnergy(10)
      ).to.emit(energyToken, "EnergyConsumed")
        .withArgs(buyer.address, 10);
    });

    it("Cannot consume more than balance", async function () {
      await expect(
        energyToken.connect(buyer).consumeEnergy(999)
      ).to.be.reverted;
    });
  });

});


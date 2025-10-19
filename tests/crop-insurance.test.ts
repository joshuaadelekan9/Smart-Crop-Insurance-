import { describe, expect, it, beforeEach } from "vitest";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const farmer1 = accounts.get("wallet_1")!;
const farmer2 = accounts.get("wallet_2")!;
const oracle = accounts.get("wallet_3")!;

describe("Smart Crop Insurance Contract", () => {
  beforeEach(() => {
    // Set up oracle address
    simnet.callPublicFn("crop-insurance", "set-oracle", [oracle], deployer);
  });

  describe("Contract Initialization", () => {
    it("should initialize with correct default values", () => {
      const stats = simnet.callReadOnlyFn("crop-insurance", "get-contract-stats", [], deployer);
      expect(stats.result).toEqual({
        "next-policy-id": 1,
        "total-premium-pool": 0,
        "oracle-address": oracle
      });
    });
  });

  describe("Oracle Management", () => {
    it("should allow contract owner to set oracle address", () => {
      const response = simnet.callPublicFn("crop-insurance", "set-oracle", [farmer1], deployer);
      expect(response.result).toBeOk(farmer1);
    });

    it("should prevent non-owner from setting oracle address", () => {
      const response = simnet.callPublicFn("crop-insurance", "set-oracle", [farmer2], farmer1);
      expect(response.result).toBeErr(100); // ERR-NOT-AUTHORIZED
    });
  });

  describe("Policy Creation", () => {
    it("should create a new policy successfully", () => {
      const response = simnet.callPublicFn(
        "crop-insurance",
        "create-policy",
        ["corn", 100000, 1000, "midwest"],
        farmer1
      );
      expect(response.result).toBeOk(1); // First policy ID
    });

    it("should store policy details correctly", () => {
      simnet.callPublicFn(
        "crop-insurance",
        "create-policy",
        ["wheat", 50000, 2000, "plains"],
        farmer1
      );
      
      const policy = simnet.callReadOnlyFn("crop-insurance", "get-policy", [1], deployer);
      expect(policy.result).toBeSome({
        farmer: farmer1,
        "crop-type": "wheat",
        "coverage-amount": 50000,
        "premium-paid": 3500, // 5% of 50000 + 2000/1000 = 2500 + 2 = 2502
        "start-block": simnet.blockHeight,
        "end-block": simnet.blockHeight + 2000,
        status: 1, // POLICY-ACTIVE
        region: "plains"
      });
    });

    it("should update farmer's policy list", () => {
      simnet.callPublicFn(
        "crop-insurance",
        "create-policy",
        ["soybeans", 75000, 1500, "south"],
        farmer1
      );
      
      const farmerPolicies = simnet.callReadOnlyFn(
        "crop-insurance",
        "get-farmer-policies",
        [farmer1],
        deployer
      );
      expect(farmerPolicies.result["policy-ids"]).toContain(1);
    });

    it("should update regional statistics", () => {
      simnet.callPublicFn(
        "crop-insurance",
        "create-policy",
        ["rice", 80000, 1200, "southeast"],
        farmer1
      );
      
      const stats = simnet.callReadOnlyFn(
        "crop-insurance",
        "get-regional-stats",
        ["southeast"],
        deployer
      );
      expect(stats.result).toEqual({
        "total-policies": 1,
        "total-coverage": 80000,
        "total-claims": 0,
        "total-payouts": 0
      });
    });
  });

  describe("Weather Claims Processing", () => {
    beforeEach(() => {
      // Create a test policy
      simnet.callPublicFn(
        "crop-insurance",
        "create-policy",
        ["corn", 100000, 1000, "midwest"],
        farmer1
      );
    });

    it("should allow oracle to submit weather data", () => {
      const response = simnet.callPublicFn(
        "crop-insurance",
        "submit-weather-claim",
        [1, 15, 95], // Low rainfall (15%), normal temperature (95%)
        oracle
      );
      expect(response.result).toBeOk(); // Should calculate payout
    });

    it("should prevent non-oracle from submitting weather data", () => {
      const response = simnet.callPublicFn(
        "crop-insurance",
        "submit-weather-claim",
        [1, 15, 95],
        farmer1
      );
      expect(response.result).toBeErr(100); // ERR-NOT-AUTHORIZED
    });

    it("should calculate correct payout for low rainfall", () => {
      const response = simnet.callPublicFn(
        "crop-insurance",
        "submit-weather-claim",
        [1, 10, 100], // 10% rainfall (triggers payout), normal temperature
        oracle
      );
      // Expected payout: (20-10)/20 * 100000 = 50000
      expect(response.result).toBeOk(50000);
    });

    it("should calculate correct payout for high temperature", () => {
      const response = simnet.callPublicFn(
        "crop-insurance",
        "submit-weather-claim",
        [1, 50, 150], // Normal rainfall, 150% temperature (triggers payout)
        oracle
      );
      // Expected payout: (150-100)/10 * 100000 = 50000  
      expect(response.result).toBeOk(50000);
    });

    it("should return zero payout for normal conditions", () => {
      const response = simnet.callPublicFn(
        "crop-insurance",
        "submit-weather-claim",
        [1, 50, 100], // Normal rainfall (50%), normal temperature (100%)
        oracle
      );
      expect(response.result).toBeOk(0);
    });

    it("should prevent duplicate weather claims", () => {
      // Submit first claim
      simnet.callPublicFn(
        "crop-insurance",
        "submit-weather-claim",
        [1, 15, 95],
        oracle
      );
      
      // Try to submit second claim
      const response = simnet.callPublicFn(
        "crop-insurance",
        "submit-weather-claim",
        [1, 10, 100],
        oracle
      );
      expect(response.result).toBeErr(107); // ERR-CLAIM-ALREADY-PROCESSED
    });

    it("should update policy status after successful claim", () => {
      simnet.callPublicFn(
        "crop-insurance",
        "submit-weather-claim",
        [1, 10, 100], // Triggers payout
        oracle
      );
      
      const policy = simnet.callReadOnlyFn("crop-insurance", "get-policy", [1], deployer);
      expect(policy.result.status).toBe(3); // POLICY-CLAIMED
    });
  });

  describe("Policy Renewal", () => {
    beforeEach(() => {
      simnet.callPublicFn(
        "crop-insurance",
        "create-policy",
        ["wheat", 60000, 800, "plains"],
        farmer1
      );
    });

    it("should allow policy owner to renew policy", () => {
      const response = simnet.callPublicFn(
        "crop-insurance",
        "renew-policy",
        [1, 500], // Extend by 500 blocks
        farmer1
      );
      expect(response.result).toBeOk(true);
    });

    it("should prevent non-owner from renewing policy", () => {
      const response = simnet.callPublicFn(
        "crop-insurance",
        "renew-policy",
        [1, 500],
        farmer2
      );
      expect(response.result).toBeErr(100); // ERR-NOT-AUTHORIZED
    });

    it("should update policy end block after renewal", () => {
      const originalPolicy = simnet.callReadOnlyFn("crop-insurance", "get-policy", [1], deployer);
      const originalEndBlock = originalPolicy.result["end-block"];
      
      simnet.callPublicFn("crop-insurance", "renew-policy", [1, 500], farmer1);
      
      const renewedPolicy = simnet.callReadOnlyFn("crop-insurance", "get-policy", [1], deployer);
      expect(renewedPolicy.result["end-block"]).toBe(originalEndBlock + 500);
    });
  });

  describe("Read-Only Functions", () => {
    beforeEach(() => {
      simnet.callPublicFn(
        "crop-insurance",
        "create-policy",
        ["barley", 40000, 600, "north"],
        farmer1
      );
    });

    it("should check payout eligibility correctly", () => {
      const eligibility = simnet.callReadOnlyFn(
        "crop-insurance",
        "check-payout-eligibility",
        [1, 15, 100], // Low rainfall scenario
        deployer
      );
      expect(eligibility.result).toBeOk(10000); // Expected payout calculation
    });

    it("should return correct regional statistics", () => {
      // Create another policy in same region
      simnet.callPublicFn(
        "crop-insurance",
        "create-policy",
        ["oats", 30000, 400, "north"],
        farmer2
      );
      
      const stats = simnet.callReadOnlyFn(
        "crop-insurance",
        "get-regional-stats",
        ["north"],
        deployer
      );
      expect(stats.result["total-policies"]).toBe(2);
    });

    it("should return weather claim details", () => {
      simnet.callPublicFn(
        "crop-insurance",
        "submit-weather-claim",
        [1, 12, 105],
        oracle
      );
      
      const claim = simnet.callReadOnlyFn(
        "crop-insurance",
        "get-weather-claim",
        [1],
        deployer
      );
      expect(claim.result).toBeSome({
        "rainfall-percentage": 12,
        "temperature-percentage": 105,
        "reported-block": simnet.blockHeight,
        "payout-amount": 16000, // Expected calculation
        processed: true
      });
    });
  });

  describe("Error Handling", () => {
    it("should handle invalid weather data", () => {
      simnet.callPublicFn(
        "crop-insurance",
        "create-policy",
        ["corn", 50000, 500, "test"],
        farmer1
      );
      
      const response = simnet.callPublicFn(
        "crop-insurance",
        "submit-weather-claim",
        [1, 250, 100], // Invalid rainfall percentage > 200
        oracle
      );
      expect(response.result).toBeErr(106); // ERR-INVALID-WEATHER-DATA
    });

    it("should handle non-existent policy", () => {
      const response = simnet.callPublicFn(
        "crop-insurance",
        "submit-weather-claim",
        [999, 50, 100], // Non-existent policy ID
        oracle
      );
      expect(response.result).toBeErr(101); // ERR-POLICY-NOT-FOUND
    });
  });
});

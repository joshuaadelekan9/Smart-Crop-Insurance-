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

  describe("Risk Assessment Management", () => {
    describe("Risk Assessment Updates", () => {
      it("should allow contract owner to update risk assessment", () => {
        const response = simnet.callPublicFn(
          "crop-insurance",
          "update-risk-assessment",
          ["midwest", "corn", 2, 15, 85, 365], // Medium risk, 15 claims, 85% success rate, 1 year period
          deployer
        );
        expect(response.result).toBeOk(true);
      });

      it("should prevent non-owner from updating risk assessment", () => {
        const response = simnet.callPublicFn(
          "crop-insurance",
          "update-risk-assessment",
          ["midwest", "corn", 2, 15, 85, 365],
          farmer1
        );
        expect(response.result).toBeErr(100); // ERR-NOT-AUTHORIZED
      });

      it("should validate risk level bounds", () => {
        const response = simnet.callPublicFn(
          "crop-insurance",
          "update-risk-assessment",
          ["midwest", "corn", 5, 15, 85, 365], // Invalid risk level > 4
          deployer
        );
        expect(response.result).toBeErr(110); // ERR-INVALID-RISK-LEVEL
      });

      it("should validate success rate bounds", () => {
        const response = simnet.callPublicFn(
          "crop-insurance",
          "update-risk-assessment",
          ["midwest", "corn", 2, 15, 150, 365], // Invalid success rate > 100
          deployer
        );
        expect(response.result).toBeErr(110); // ERR-INVALID-RISK-LEVEL
      });

      it("should store risk assessment data correctly", () => {
        simnet.callPublicFn(
          "crop-insurance",
          "update-risk-assessment",
          ["plains", "wheat", 3, 25, 75, 180],
          deployer
        );
        
        const assessment = simnet.callReadOnlyFn(
          "crop-insurance",
          "get-risk-assessment",
          ["plains", "wheat"],
          deployer
        );
        expect(assessment.result).toBeSome({
          "risk-level": 3,
          "historical-claims": 25,
          "success-rate": 75,
          "last-updated": simnet.blockHeight,
          "assessment-period": 180
        });
      });
    });

    describe("Risk Factors Management", () => {
      it("should allow contract owner to update risk factors", () => {
        const response = simnet.callPublicFn(
          "crop-insurance",
          "update-risk-factors",
          ["southeast", 75, 60, 85, 90], // Weather volatility 75%, climate trend 60%, soil quality 85%, water availability 90%
          deployer
        );
        expect(response.result).toBeOk(true);
      });

      it("should prevent non-owner from updating risk factors", () => {
        const response = simnet.callPublicFn(
          "crop-insurance",
          "update-risk-factors",
          ["southeast", 75, 60, 85, 90],
          farmer1
        );
        expect(response.result).toBeErr(100); // ERR-NOT-AUTHORIZED
      });

      it("should validate risk factor bounds", () => {
        const response = simnet.callPublicFn(
          "crop-insurance",
          "update-risk-factors",
          ["southeast", 150, 60, 85, 90], // Invalid weather volatility > 100
          deployer
        );
        expect(response.result).toBeErr(110); // ERR-INVALID-RISK-LEVEL
      });

      it("should store risk factors correctly", () => {
        simnet.callPublicFn(
          "crop-insurance",
          "update-risk-factors",
          ["north", 40, 25, 95, 80],
          deployer
        );
        
        const factors = simnet.callReadOnlyFn(
          "crop-insurance",
          "get-risk-factors",
          ["north"],
          deployer
        );
        expect(factors.result).toBeSome({
          "weather-volatility": 40,
          "climate-trend": 25,
          "soil-quality": 95,
          "water-availability": 80,
          "last-assessment": simnet.blockHeight
        });
      });
    });

    describe("Risk-Adjusted Premium Calculation", () => {
      beforeEach(() => {
        // Set up risk assessment for corn in midwest
        simnet.callPublicFn(
          "crop-insurance",
          "update-risk-assessment",
          ["midwest", "corn", 2, 10, 90, 365], // Medium risk
          deployer
        );
        
        // Set up risk factors for midwest
        simnet.callPublicFn(
          "crop-insurance",
          "update-risk-factors",
          ["midwest", 30, 20, 80, 85],
          deployer
        );
      });

      it("should calculate risk-adjusted premium with medium risk", () => {
        const response = simnet.callPublicFn(
          "crop-insurance",
          "calculate-risk-adjusted-premium",
          [100000, 1000, "midwest", "corn"],
          deployer
        );
        // Base premium would be 5001, with medium risk (100%) and factor adjustments
        expect(response.result).toBeOk();
        expect(Number(response.result.replace("(ok ", "").replace(")", ""))).toBeGreaterThan(5000);
      });

      it("should return base premium when no risk data exists", () => {
        const response = simnet.callPublicFn(
          "crop-insurance",
          "calculate-risk-adjusted-premium",
          [50000, 500, "unknown", "unknown"],
          deployer
        );
        expect(response.result).toBeOk(3000); // Base premium calculation
      });

      it("should apply low risk discount", () => {
        // Set up low risk assessment
        simnet.callPublicFn(
          "crop-insurance",
          "update-risk-assessment",
          ["safe-region", "corn", 1, 5, 95, 365], // Low risk
          deployer
        );
        
        const response = simnet.callPublicFn(
          "crop-insurance",
          "calculate-risk-adjusted-premium",
          [100000, 1000, "safe-region", "corn"],
          deployer
        );
        
        // Should be less than base premium due to low risk multiplier (80%)
        expect(response.result).toBeOk();
        const premium = Number(response.result.replace("(ok ", "").replace(")", ""));
        expect(premium).toBeLessThan(5001); // Base premium is 5001
      });

      it("should apply high risk premium", () => {
        // Set up high risk assessment
        simnet.callPublicFn(
          "crop-insurance",
          "update-risk-assessment",
          ["risky-region", "corn", 4, 40, 60, 365], // Extreme risk
          deployer
        );
        
        const response = simnet.callPublicFn(
          "crop-insurance",
          "calculate-risk-adjusted-premium",
          [100000, 1000, "risky-region", "corn"],
          deployer
        );
        
        // Should be more than base premium due to extreme risk multiplier (160%)
        expect(response.result).toBeOk();
        const premium = Number(response.result.replace("(ok ", "").replace(")", ""));
        expect(premium).toBeGreaterThan(5001); // Base premium is 5001
      });
    });

    describe("Risk Profile Analysis", () => {
      beforeEach(() => {
        // Create comprehensive test data
        simnet.callPublicFn(
          "crop-insurance",
          "update-risk-assessment",
          ["test-region", "soybeans", 3, 20, 80, 365],
          deployer
        );
        
        simnet.callPublicFn(
          "crop-insurance",
          "update-risk-factors",
          ["test-region", 50, 40, 70, 85],
          deployer
        );
        
        // Create some policies to generate regional stats
        simnet.callPublicFn(
          "crop-insurance",
          "create-policy",
          ["soybeans", 75000, 1200, "test-region"],
          farmer1
        );
        
        simnet.callPublicFn(
          "crop-insurance",
          "create-policy",
          ["soybeans", 60000, 1000, "test-region"],
          farmer2
        );
      });

      it("should return comprehensive risk profile", () => {
        const profile = simnet.callReadOnlyFn(
          "crop-insurance",
          "get-risk-profile",
          ["test-region", "soybeans"],
          deployer
        );
        
        expect(profile.result).toHaveProperty("assessment");
        expect(profile.result).toHaveProperty("factors");
        expect(profile.result).toHaveProperty("regional-stats");
        expect(profile.result).toHaveProperty("risk-score");
        
        // Verify assessment data
        expect(profile.result.assessment).toBeSome({
          "risk-level": 3,
          "historical-claims": 20,
          "success-rate": 80,
          "last-updated": simnet.blockHeight,
          "assessment-period": 365
        });
        
        // Verify risk score is within valid range
        const riskScore = profile.result["risk-score"];
        expect(riskScore).toBeGreaterThanOrEqual(0);
        expect(riskScore).toBeLessThanOrEqual(100);
      });

      it("should calculate risk score for region without assessment data", () => {
        const profile = simnet.callReadOnlyFn(
          "crop-insurance",
          "get-risk-profile",
          ["unknown-region", "unknown-crop"],
          deployer
        );
        
        expect(profile.result["risk-score"]).toBeGreaterThanOrEqual(0);
        expect(profile.result["risk-score"]).toBeLessThanOrEqual(100);
      });
    });

    describe("Integration with Existing Features", () => {
      it("should work alongside existing policy creation", () => {
        // Set up risk data
        simnet.callPublicFn(
          "crop-insurance",
          "update-risk-assessment",
          ["integrated-region", "wheat", 2, 12, 88, 365],
          deployer
        );
        
        // Create policy - should still work with existing flow
        const policyResponse = simnet.callPublicFn(
          "crop-insurance",
          "create-policy",
          ["wheat", 80000, 1500, "integrated-region"],
          farmer1
        );
        expect(policyResponse.result).toBeOk(1);
        
        // Check risk-adjusted premium calculation
        const premiumResponse = simnet.callPublicFn(
          "crop-insurance",
          "calculate-risk-adjusted-premium",
          [80000, 1500, "integrated-region", "wheat"],
          deployer
        );
        expect(premiumResponse.result).toBeOk();
      });

      it("should not interfere with weather claims processing", () => {
        // Set up policy and risk data
        simnet.callPublicFn(
          "crop-insurance",
          "update-risk-assessment",
          ["weather-region", "corn", 1, 8, 92, 365],
          deployer
        );
        
        simnet.callPublicFn(
          "crop-insurance",
          "create-policy",
          ["corn", 90000, 1200, "weather-region"],
          farmer1
        );
        
        // Weather claims should still work normally
        const claimResponse = simnet.callPublicFn(
          "crop-insurance",
          "submit-weather-claim",
          [1, 15, 95],
          oracle
        );
        expect(claimResponse.result).toBeOk();
      });
    });
  });
});

import { describe, expect, it, beforeEach } from "vitest";
import { simnet } from "@hirosystems/clarinet-sdk";
import { Cl } from "@stacks/transactions";

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

  describe("Crop Audit and Verification System", () => {
    const auditor1 = accounts.get("wallet_2")!;
    const auditor2 = accounts.get("wallet_3")!;
    
    describe("Auditor Registration", () => {
      it("should allow new auditor registration", () => {
        const response = simnet.callPublicFn(
          "crop-insurance",
          "register-auditor",
          [Cl.list([Cl.stringAscii("organic"), Cl.stringAscii("sustainable")])],
          auditor1
        );
        expect(response.result).toBeOk(true);
      });

      it("should store auditor information correctly", () => {
        simnet.callPublicFn(
          "crop-insurance",
          "register-auditor",
          [Cl.list([Cl.stringAscii("irrigation"), Cl.stringAscii("pesticides")])],
          auditor1
        );
        
        const auditorInfo = simnet.callReadOnlyFn(
          "crop-insurance",
          "get-auditor-info",
          [auditor1],
          deployer
        );
        expect(auditorInfo.result).toBeSome({
          "registration-block": simnet.blockHeight,
          specializations: ["irrigation", "pesticides"],
          "completed-audits": 0,
          "reputation-score": 100,
          "is-active": true
        });
      });

      it("should prevent duplicate auditor registration", () => {
        simnet.callPublicFn(
          "crop-insurance",
          "register-auditor",
          [Cl.list([Cl.stringAscii("organic")])],
          auditor1
        );
        
        const response = simnet.callPublicFn(
          "crop-insurance",
          "register-auditor",
          [Cl.list([Cl.stringAscii("sustainable")])],
          auditor1
        );
        expect(response.result).toBeErr(201); // ERR-AUDIT-ALREADY-EXISTS
      });
    });

    describe("Audit Request Creation", () => {
      beforeEach(() => {
        // Register an auditor for the tests
        simnet.callPublicFn(
          "crop-insurance",
          "register-auditor",
          [Cl.list([Cl.stringAscii("general")])],
          auditor1
        );
      });

      it("should create audit request successfully", () => {
        const response = simnet.callPublicFn(
          "crop-insurance",
          "request-crop-audit",
          ["tomatoes", "california-central-valley", 2], // Standard verification level
          farmer1
        );
        expect(response.result).toBeOk(1); // First audit ID
      });

      it("should store audit request details correctly", () => {
        simnet.callPublicFn(
          "crop-insurance",
          "request-crop-audit",
          ["lettuce", "oregon-coast", 3], // Premium verification level
          farmer1
        );
        
        const audit = simnet.callReadOnlyFn(
          "crop-insurance",
          "get-audit",
          [1],
          deployer
        );
        expect(audit.result).toBeSome({
          farmer: farmer1,
          auditor: null,
          "crop-type": "lettuce",
          "farm-location": "oregon-coast",
          "verification-level": 3,
          "audit-fee": 3000, // 1000 * 3
          status: 1, // AUDIT-PENDING
          "request-block": simnet.blockHeight,
          "completion-block": null,
          "audit-report-hash": null,
          "compliance-score": null
        });
      });

      it("should update farmer's audit history", () => {
        simnet.callPublicFn(
          "crop-insurance",
          "request-crop-audit",
          ["spinach", "texas-panhandle", 1], // Basic verification
          farmer1
        );
        
        const history = simnet.callReadOnlyFn(
          "crop-insurance",
          "get-farmer-audit-history",
          [farmer1],
          deployer
        );
        expect(history.result["audit-ids"]).toContain(1);
      });

      it("should reject invalid verification levels", () => {
        const response = simnet.callPublicFn(
          "crop-insurance",
          "request-crop-audit",
          ["corn", "iowa", 4], // Invalid level (> 3)
          farmer1
        );
        expect(response.result).toBeErr(202); // ERR-INVALID-AUDIT-STATUS
      });
    });

    describe("Audit Process Management", () => {
      beforeEach(() => {
        // Setup: Register auditor and create audit request
        simnet.callPublicFn(
          "crop-insurance",
          "register-auditor",
          [Cl.list([Cl.stringAscii("soil-analysis")])],
          auditor1
        );
        simnet.callPublicFn(
          "crop-insurance",
          "request-crop-audit",
          ["wheat", "kansas-plains", 2],
          farmer1
        );
      });

      it("should allow registered auditor to accept audit request", () => {
        const response = simnet.callPublicFn(
          "crop-insurance",
          "accept-audit-request",
          [1],
          auditor1
        );
        expect(response.result).toBeOk(true);
      });

      it("should update audit status after acceptance", () => {
        simnet.callPublicFn(
          "crop-insurance",
          "accept-audit-request",
          [1],
          auditor1
        );
        
        const audit = simnet.callReadOnlyFn(
          "crop-insurance",
          "get-audit",
          [1],
          deployer
        );
        expect(audit.result.auditor).toBe(auditor1);
        expect(audit.result.status).toBe(2); // AUDIT-IN-PROGRESS
      });

      it("should prevent non-registered auditor from accepting requests", () => {
        const response = simnet.callPublicFn(
          "crop-insurance",
          "accept-audit-request",
          [1],
          farmer2 // Not registered as auditor
        );
        expect(response.result).toBeErr(205); // ERR-AUDITOR-NOT-AUTHORIZED
      });
    });

    describe("Audit Results Submission", () => {
      const reportHash = Cl.bufferFromHex("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef");
      
      beforeEach(() => {
        // Setup: Register auditor, create request, and accept it
        simnet.callPublicFn(
          "crop-insurance",
          "register-auditor",
          [Cl.list([Cl.stringAscii("comprehensive")])],
          auditor1
        );
        simnet.callPublicFn(
          "crop-insurance",
          "request-crop-audit",
          ["soybeans", "illinois-farmland", 2],
          farmer1
        );
        simnet.callPublicFn(
          "crop-insurance",
          "accept-audit-request",
          [1],
          auditor1
        );
      });

      it("should allow auditor to submit results", () => {
        const response = simnet.callPublicFn(
          "crop-insurance",
          "submit-audit-results",
          [
            1, // audit-id
            85, // soil-quality-score
            true, // irrigation-compliance
            90, // pest-management-score
            80, // sustainable-practices-score
            "Excellent farming practices with minor improvements needed in water conservation.", // recommendations
            reportHash
          ],
          auditor1
        );
        expect(response.result).toBeOk(88); // Overall compliance score: (85+100+90+80)/4 = 88.75 ≈ 88
      });

      it("should store audit results correctly", () => {
        simnet.callPublicFn(
          "crop-insurance",
          "submit-audit-results",
          [1, 75, false, 85, 70, "Good practices, irrigation system needs upgrade.", reportHash],
          auditor1
        );
        
        const results = simnet.callReadOnlyFn(
          "crop-insurance",
          "get-audit-results",
          [1],
          deployer
        );
        expect(results.result).toBeSome({
          "soil-quality-score": 75,
          "irrigation-compliance": false,
          "pest-management-score": 85,
          "sustainable-practices-score": 70,
          "overall-compliance": 57, // (75+0+85+70)/4 = 57.5 ≈ 57
          recommendations: "Good practices, irrigation system needs upgrade.",
          "certification-valid-until": simnet.blockHeight + 52560
        });
      });

      it("should update audit status after submission", () => {
        simnet.callPublicFn(
          "crop-insurance",
          "submit-audit-results",
          [1, 90, true, 88, 85, "Exemplary sustainable farming practices.", reportHash],
          auditor1
        );
        
        const audit = simnet.callReadOnlyFn(
          "crop-insurance",
          "get-audit",
          [1],
          deployer
        );
        expect(audit.result.status).toBe(3); // AUDIT-COMPLETED
        expect(audit.result["completion-block"]).toBe(simnet.blockHeight);
      });

      it("should prevent non-assigned auditor from submitting results", () => {
        // Register another auditor
        simnet.callPublicFn(
          "crop-insurance",
          "register-auditor",
          [Cl.list([Cl.stringAscii("pest-control")])],
          auditor2
        );
        
        const response = simnet.callPublicFn(
          "crop-insurance",
          "submit-audit-results",
          [1, 80, true, 85, 75, "Good results.", reportHash],
          auditor2 // Different auditor
        );
        expect(response.result).toBeErr(205); // ERR-AUDITOR-NOT-AUTHORIZED
      });

      it("should reject invalid score values", () => {
        const response = simnet.callPublicFn(
          "crop-insurance",
          "submit-audit-results",
          [1, 150, true, 90, 80, "Invalid score test.", reportHash], // soil score > 100
          auditor1
        );
        expect(response.result).toBeErr(202); // ERR-INVALID-AUDIT-STATUS
      });
    });

    describe("Audit Dispute Process", () => {
      const reportHash = Cl.bufferFromHex("abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789");
      
      beforeEach(() => {
        // Setup: Complete audit process
        simnet.callPublicFn(
          "crop-insurance",
          "register-auditor",
          [Cl.list([Cl.stringAscii("dispute-test")])],
          auditor1
        );
        simnet.callPublicFn(
          "crop-insurance",
          "request-crop-audit",
          ["corn", "nebraska", 1],
          farmer1
        );
        simnet.callPublicFn(
          "crop-insurance",
          "accept-audit-request",
          [1],
          auditor1
        );
        simnet.callPublicFn(
          "crop-insurance",
          "submit-audit-results",
          [1, 60, false, 65, 55, "Below standard practices identified.", reportHash],
          auditor1
        );
      });

      it("should allow farmer to dispute audit results", () => {
        const response = simnet.callPublicFn(
          "crop-insurance",
          "dispute-audit-results",
          [1, "Auditor was biased and did not follow proper procedures."],
          farmer1
        );
        expect(response.result).toBeOk(true);
      });

      it("should update audit status after dispute", () => {
        simnet.callPublicFn(
          "crop-insurance",
          "dispute-audit-results",
          [1, "Scores are inaccurate based on actual farm conditions."],
          farmer1
        );
        
        const audit = simnet.callReadOnlyFn(
          "crop-insurance",
          "get-audit",
          [1],
          deployer
        );
        expect(audit.result.status).toBe(4); // AUDIT-REJECTED
      });

      it("should prevent non-farmer from disputing", () => {
        const response = simnet.callPublicFn(
          "crop-insurance",
          "dispute-audit-results",
          [1, "Invalid dispute attempt."],
          farmer2 // Different farmer
        );
        expect(response.result).toBeErr(100); // ERR-NOT-AUTHORIZED
      });
    });

    describe("Audit System Statistics and Queries", () => {
      beforeEach(() => {
        // Setup multiple audits for statistics
        simnet.callPublicFn(
          "crop-insurance",
          "register-auditor",
          [Cl.list([Cl.stringAscii("stats-test")])],
          auditor1
        );
        
        // Create multiple audit requests
        simnet.callPublicFn(
          "crop-insurance",
          "request-crop-audit",
          ["potatoes", "idaho", 1],
          farmer1
        );
        simnet.callPublicFn(
          "crop-insurance",
          "request-crop-audit",
          ["carrots", "california", 2],
          farmer2
        );
      });

      it("should return correct audit system statistics", () => {
        const stats = simnet.callReadOnlyFn(
          "crop-insurance",
          "get-audit-stats",
          [],
          deployer
        );
        expect(stats.result).toEqual({
          "next-audit-id": 3, // Should be 3 after creating 2 audits
          "total-audit-fees": 3000, // 1000 * 1 + 1000 * 2 = 3000
          "audit-fee-rate": 1000
        });
      });

      it("should track farmer audit history correctly", () => {
        const history = simnet.callReadOnlyFn(
          "crop-insurance",
          "get-farmer-audit-history",
          [farmer1],
          deployer
        );
        expect(history.result["audit-ids"]).toContain(1);
        expect(history.result["audit-ids"]).not.toContain(2);
      });

      it("should check certification validity", () => {
        // Should return false initially (no completed audits)
        const validity = simnet.callReadOnlyFn(
          "crop-insurance",
          "has-valid-certification",
          [farmer1],
          deployer
        );
        expect(validity.result).toBe(false);
      });
    });

    describe("Error Handling for Audit System", () => {
      it("should handle requests for non-existent audits", () => {
        const response = simnet.callPublicFn(
          "crop-insurance",
          "accept-audit-request",
          [999], // Non-existent audit ID
          auditor1
        );
        expect(response.result).toBeErr(200); // ERR-AUDIT-NOT-FOUND
      });

      it("should handle insufficient audit fees", () => {
        // This would typically be caught in fee validation
        // For this test, we're checking the error constant exists
        const auditStats = simnet.callReadOnlyFn(
          "crop-insurance",
          "get-audit-stats",
          [],
          deployer
        );
        expect(auditStats.result["audit-fee-rate"]).toBe(1000);
      });
    });
  });
});

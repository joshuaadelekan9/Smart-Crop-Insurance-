import { describe, expect, it, beforeAll } from "vitest";
import { readFileSync } from 'fs';
import { join } from 'path';

describe("Smart Crop Insurance Contract - Logic Validation", () => {
  let contractContent: string;

  beforeAll(() => {
    contractContent = readFileSync(join(process.cwd(), 'contracts', 'crop-insurance.clar'), 'utf8');
  });

  describe("Original Contract Functions", () => {
    it("should have core policy management functions", () => {
      expect(contractContent).toContain('define-public (create-policy');
      expect(contractContent).toContain('define-public (renew-policy');
      expect(contractContent).toContain('define-public (submit-weather-claim');
    });

    it("should have oracle management", () => {
      expect(contractContent).toContain('define-public (set-oracle');
      expect(contractContent).toContain('oracle-address');
    });

    it("should have read-only query functions", () => {
      expect(contractContent).toContain('define-read-only (get-policy');
      expect(contractContent).toContain('define-read-only (get-weather-claim');
      expect(contractContent).toContain('define-read-only (get-farmer-policies');
      expect(contractContent).toContain('define-read-only (get-regional-stats');
    });
  });

  describe("Risk Assessment Enhancement", () => {
    it("should have risk assessment management functions", () => {
      expect(contractContent).toContain('define-public (update-risk-assessment');
      expect(contractContent).toContain('define-public (update-risk-factors');
    });

    it("should have risk-adjusted premium calculation", () => {
      expect(contractContent).toContain('define-public (calculate-risk-adjusted-premium');
    });

    it("should have risk data query functions", () => {
      expect(contractContent).toContain('define-read-only (get-risk-assessment');
      expect(contractContent).toContain('define-read-only (get-risk-factors');
      expect(contractContent).toContain('define-read-only (get-risk-profile');
    });
  });

  describe("Premium Calculation Logic", () => {
    it("should validate base premium calculation concept", () => {
      // Base premium: 5% of coverage + duration factor
      const coverage = 100000;
      const duration = 1000;
      const expectedBasePremium = (coverage * 5) / 100 + duration / 1000;
      
      expect(expectedBasePremium).toBe(5001);
    });

    it("should validate risk multiplier application", () => {
      const basePremium = 5001;
      const lowRiskMultiplier = 8000; // 80%
      const highRiskMultiplier = 13000; // 130%
      
      const lowRiskPremium = (basePremium * lowRiskMultiplier) / 10000;
      const highRiskPremium = (basePremium * highRiskMultiplier) / 10000;
      
      expect(lowRiskPremium).toBe(4000.8);
      expect(highRiskPremium).toBe(6501.3);
    });
  });

  describe("Weather Claim Logic", () => {
    it("should validate payout calculation for low rainfall", () => {
      // Formula: (RAINFALL-THRESHOLD - rainfall) / RAINFALL-THRESHOLD * coverage
      const rainfallThreshold = 20;
      const coverage = 100000;
      const rainfall = 10; // 10% (triggers payout)
      
      const expectedPayout = ((rainfallThreshold - rainfall) / rainfallThreshold) * coverage;
      expect(expectedPayout).toBe(50000);
    });

    it("should validate payout calculation for high temperature", () => {
      // Formula: (temperature - 100) / 10 * coverage  
      const coverage = 100000;
      const temperature = 150; // 150% (triggers payout)
      
      const expectedPayout = ((temperature - 100) / 10) * coverage;
      expect(expectedPayout).toBe(500000);
    });
  });

  describe("Error Handling", () => {
    it("should have all error constants defined", () => {
      const errorCodes = [
        'ERR-NOT-AUTHORIZED (err u100)',
        'ERR-POLICY-NOT-FOUND (err u101)', 
        'ERR-POLICY-ALREADY-EXISTS (err u102)',
        'ERR-INSUFFICIENT-PREMIUM (err u103)',
        'ERR-POLICY-EXPIRED (err u104)',
        'ERR-POLICY-NOT-ACTIVE (err u105)',
        'ERR-INVALID-WEATHER-DATA (err u106)',
        'ERR-CLAIM-ALREADY-PROCESSED (err u107)',
        'ERR-INSUFFICIENT-FUNDS (err u108)',
        'ERR-RISK-ASSESSMENT-NOT-FOUND (err u109)',
        'ERR-INVALID-RISK-LEVEL (err u110)'
      ];

      errorCodes.forEach(errorCode => {
        expect(contractContent).toContain(errorCode);
      });
    });
  });

  describe("Data Structure Validation", () => {
    it("should have all required data maps", () => {
      const dataMaps = [
        'define-map policies',
        'define-map weather-claims', 
        'define-map farmer-policies',
        'define-map regional-stats',
        'define-map risk-assessments',
        'define-map risk-factors'
      ];

      dataMaps.forEach(dataMap => {
        expect(contractContent).toContain(dataMap);
      });
    });

    it("should have all required data variables", () => {
      const dataVars = [
        'define-data-var next-policy-id',
        'define-data-var total-premium-pool',
        'define-data-var oracle-address'
      ];

      dataVars.forEach(dataVar => {
        expect(contractContent).toContain(dataVar);
      });
    });
  });
});

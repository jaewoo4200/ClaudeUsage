import XCTest
@testable import ClaudeUsage

final class OpenAIUsageDataTests: XCTestCase {
    func testDecodesCurrentWhamShapeWithModelSpecificWindows() throws {
        let usage = try decode(
            """
            {
              "plan_type": "pro",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 16,
                  "reset_at": 1783634265,
                  "limit_window_seconds": 18000
                },
                "secondary_window": {
                  "used_percent": 30,
                  "reset_at": 1783904355,
                  "limit_window_seconds": 604800
                }
              },
              "additional_rate_limits": [
                {
                  "limit_name": "GPT-5.3-Codex-Spark",
                  "metered_feature": "codex_bengalfox",
                  "rate_limit": {
                    "primary_window": {
                      "used_percent": 2,
                      "reset_at": 1783645702,
                      "limit_window_seconds": 18000
                    },
                    "secondary_window": {
                      "used_percent": 4,
                      "reset_at": 1784232502,
                      "limit_window_seconds": 604800
                    }
                  }
                }
              ]
            }
            """
        )

        XCTAssertEqual(usage.planDisplayName, "Pro")
        XCTAssertEqual(usage.counters.map(\.id), [
            "openai-standard-five-hour",
            "openai-standard-weekly",
            "openai-model-codex-bengalfox-five-hour",
            "openai-model-codex-bengalfox-weekly"
        ])
        XCTAssertEqual(usage.counters.map(\.window.usedPercent), [16, 30, 2, 4])
        XCTAssertEqual(usage.counters[2].name, "GPT-5.3-Codex-Spark")
    }

    func testNewGPT56ModelsAppearWithoutHardcodedNames() throws {
        let usage = try decode(
            """
            {
              "plan_type": "enterprise",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 8,
                  "limit_window_seconds": 18000,
                  "reset_after_seconds": 900
                }
              },
              "additional_rate_limits": [
                {
                  "limit_name": "GPT-5.6-Sol",
                  "metered_feature": "gpt_5_6_sol",
                  "rate_limit": {
                    "primary_window": {
                      "used_percent": 24,
                      "limit_window_seconds": 18000,
                      "reset_after_seconds": 1200
                    },
                    "secondary_window": {
                      "used_percent": 11,
                      "limit_window_seconds": 604800,
                      "reset_after_seconds": 7200
                    }
                  }
                },
                {
                  "limit_name": "GPT-5.6-Terra",
                  "metered_feature": "gpt_5_6_terra",
                  "rate_limit": {
                    "primary_window": {
                      "used_percent": 7,
                      "limit_window_seconds": 18000,
                      "reset_after_seconds": 1800
                    }
                  }
                }
              ]
            }
            """
        )

        XCTAssertEqual(usage.planDisplayName, "Enterprise")
        XCTAssertEqual(usage.counters.compactMap(\.name), [
            "GPT-5.6-Sol",
            "GPT-5.6-Sol",
            "GPT-5.6-Terra"
        ])
        XCTAssertTrue(usage.counters.contains { $0.id == "openai-model-gpt-5-6-sol-weekly" })
        XCTAssertTrue(usage.counters.contains { $0.id == "openai-model-gpt-5-6-terra-five-hour" })
    }

    func testMalformedAndSplitAdditionalLimitsDoNotBreakBaseUsage() throws {
        let usage = try decode(
            """
            {
              "rate_limit": {
                "primary_window": {
                  "used_percent": "22",
                  "reset_at": "1783634265",
                  "limit_window_seconds": "18000"
                }
              },
              "additional_rate_limits": [
                42,
                {
                  "limit_name": "GPT-5.6-Luna",
                  "metered_feature": "gpt_5_6_luna",
                  "rate_limit": {
                    "primary_window": {
                      "used_percent": 9,
                      "limit_window_seconds": 18000
                    }
                  }
                },
                {
                  "limit_name": "GPT-5.6-Luna Weekly",
                  "metered_feature": "gpt_5_6_luna",
                  "rate_limit": {
                    "primary_window": {
                      "used_percent": 31,
                      "limit_window_seconds": 604800
                    }
                  }
                }
              ]
            }
            """
        )

        XCTAssertEqual(usage.counters.first?.window.usedPercent, 22)
        XCTAssertEqual(usage.counters.filter { $0.scope == .model }.map(\.window.usedPercent), [9, 31])
        XCTAssertEqual(Set(usage.counters.map(\.id)).count, usage.counters.count)
    }

    private func decode(_ json: String) throws -> OpenAIUsageData {
        try JSONDecoder().decode(OpenAIUsageData.self, from: Data(json.utf8))
    }
}

import Testing
@testable import ShguideCore

@Suite("DestructivePolicy")
struct DestructivePolicyTests {
    @Test func plainRm() {
        #expect(DestructivePolicy.isDestructive("rm foo.txt"))
        #expect(DestructivePolicy.isDestructive("rm -rf ./build"))
    }

    @Test func ddIsDestructive() {
        #expect(DestructivePolicy.isDestructive("dd if=/dev/zero of=/dev/sda bs=1M"))
        #expect(DestructivePolicy.isDestructive("dd if=foo of=bar"))
    }

    @Test func forkBombFlagged() {
        #expect(DestructivePolicy.isDestructive(":(){:|:&};:"))
    }

    @Test func recursiveChmodFlagged() {
        #expect(DestructivePolicy.isDestructive("chmod -R 777 /etc"))
    }

    @Test func grepIsSafe() {
        #expect(!DestructivePolicy.isDestructive("grep -r ERROR /var/log/nginx"))
    }

    @Test func findWithoutDeleteIsSafe() {
        #expect(!DestructivePolicy.isDestructive("find . -type f -size +500M"))
    }

    @Test func pipelineFlagsAnyDangerousSegment() {
        #expect(DestructivePolicy.isDestructive("ls -la | xargs rm"))
    }

    @Test func redirectToDevSdFlagged() {
        #expect(DestructivePolicy.isDestructive("cat foo > /dev/sda"))
    }

    @Test func effectiveRiskUpgradesSafeLabelOnDangerousCommand() {
        let risk = DestructivePolicy.effectiveRisk(command: "rm -rf ./build", modelLabel: "safe")
        #expect(risk == .destructive)
    }

    @Test func effectiveRiskRespectsCautionLabelOnSafeCommand() {
        let risk = DestructivePolicy.effectiveRisk(command: "tee file.txt", modelLabel: "caution")
        #expect(risk == .caution)
    }
}

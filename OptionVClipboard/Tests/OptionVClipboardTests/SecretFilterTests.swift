import Testing
@testable import OptionVClipboard

@Suite
struct SecretFilterTests {
    @Test
    func rejectsPrivateKeyMaterial() {
        let filter = SecretFilter(skipShortOneTimeCodes: true)

        #expect(filter.shouldReject("""
        -----BEGIN PRIVATE KEY-----
        abc123
        -----END PRIVATE KEY-----
        """))
    }

    @Test
    func rejectsSecretLabels() {
        let filter = SecretFilter(skipShortOneTimeCodes: true)

        #expect(filter.shouldReject("token=super-secret-value"))
        #expect(filter.shouldReject("Authorization: Bearer abcdef"))
    }

    @Test
    func rejectsShortOneTimeCodesWhenEnabled() {
        let filter = SecretFilter(skipShortOneTimeCodes: true)

        #expect(filter.shouldReject("123456"))
    }

    @Test
    func allowsShortOneTimeCodesWhenDisabled() {
        let filter = SecretFilter(skipShortOneTimeCodes: false)

        #expect(filter.shouldReject("123456") == false)
    }

    @Test
    func rejectsLongRandomTokens() {
        let filter = SecretFilter(skipShortOneTimeCodes: true)

        #expect(filter.shouldReject("aB3kLm9QwX2zT5nR7uV1pH4sJ8dF0gY6"))
    }
}

//
//  PGPAgent.swift
//  passKitTests
//
//  Created by Yishi Lin on 2019/7/17.
//  Copyright © 2019 Bob Sun. All rights reserved.
//

import XCTest
import SwiftyUserDefaults

@testable import passKit

class PGPAgentTest: XCTestCase {
    private var keychain: KeyStore!
    private var pgpAgent: PGPAgent!

    private let testData = "Hello World!".data(using: .utf8)!

    override func setUp() {
        super.setUp()
        keychain = DictBasedKeychain()
        pgpAgent = PGPAgent(keyStore: keychain)
        UserDefaults().removePersistentDomain(forName: "SharedDefaultsForPGPAgentTest")
        passKit.Defaults = DefaultsAdapter(defaults: UserDefaults(suiteName: "SharedDefaultsForPGPAgentTest")!, keyStore: DefaultsKeys())
    }

    override func tearDown() {
        keychain.removeAllContent()
        UserDefaults().removePersistentDomain(forName: "SharedDefaultsForPGPAgentTest")
        super.tearDown()
    }

    func basicEncryptDecrypt(using pgpAgent: PGPAgent, keyID: String, encryptKeyID: String? = nil, requestPassphrase: (String) -> String = requestPGPKeyPassphrase, encryptInArmored: Bool = true, encryptInArmoredNow: Bool = true) throws -> Data? {
        passKit.Defaults.encryptInArmored = encryptInArmored
        let encryptedData = try pgpAgent.encrypt(plainData: testData, keyID: keyID)
        passKit.Defaults.encryptInArmored = encryptInArmoredNow
        return try pgpAgent.decrypt(encryptedData: encryptedData, keyID: encryptKeyID ?? keyID, requestPGPKeyPassphrase: requestPassphrase)
    }

    func testMultiKeys() throws {
        try [
            RSA2048_RSA4096,
            ED25519_NISTP384
        ].forEach { testKeyInfo in
            let keychain = DictBasedKeychain()
            let pgpAgent = PGPAgent(keyStore: keychain)
            try KeyFileManager(keyType: PgpKey.PUBLIC, keyPath: "", keyHandler: keychain.add).importKey(from: testKeyInfo.publicKey)
            try KeyFileManager(keyType: PgpKey.PRIVATE, keyPath: "", keyHandler: keychain.add).importKey(from: testKeyInfo.privateKey)
            XCTAssert(pgpAgent.isPrepared)
            try pgpAgent.initKeys()
            try [
                (true, true), (true, false), (false, true), (false, false)
            ].forEach{ a, b in
                for id in testKeyInfo.fingerprint {
                    XCTAssertEqual(try basicEncryptDecrypt(using: pgpAgent, keyID: id, encryptInArmored: a, encryptInArmoredNow: b), testData)
                }
            }
        }
    }

    func testBasicEncryptDecrypt() throws {
        try [
            RSA2048,
            RSA2048_SUB,
            RSA4096,
            RSA4096_SUB,
            ED25519,
            ED25519_SUB,
            NISTP384,
        ].forEach { testKeyInfo in
            let keychain = DictBasedKeychain()
            let pgpAgent = PGPAgent(keyStore: keychain)
            try KeyFileManager(keyType: PgpKey.PUBLIC, keyPath: "", keyHandler: keychain.add).importKey(from: testKeyInfo.publicKey)
            try KeyFileManager(keyType: PgpKey.PRIVATE, keyPath: "", keyHandler: keychain.add).importKey(from: testKeyInfo.privateKey)
            XCTAssert(pgpAgent.isPrepared)
            try pgpAgent.initKeys()
            XCTAssert(try pgpAgent.getKeyID().first!.lowercased().hasSuffix(testKeyInfo.fingerprint))
            try [
                (true, true), (true, false), (false, true), (false, false)
            ].forEach{ a, b in
                XCTAssertEqual(try basicEncryptDecrypt(using: pgpAgent, keyID: testKeyInfo.fingerprint, encryptInArmored: a, encryptInArmoredNow: b), testData)
            }
        }
    }

    func testNoPrivateKey() throws {
        try KeyFileManager(keyType: PgpKey.PUBLIC, keyPath: "", keyHandler: keychain.add).importKey(from: RSA2048.publicKey)
        XCTAssertFalse(pgpAgent.isPrepared)
        XCTAssertThrowsError(try pgpAgent.initKeys()) {
            XCTAssertEqual($0 as! AppError, AppError.KeyImport)
        }
        XCTAssertThrowsError(try basicEncryptDecrypt(using: pgpAgent, keyID: RSA2048.fingerprint)) {
            XCTAssertEqual($0 as! AppError, AppError.KeyImport)
        }
    }

    func testInterchangePublicAndPrivateKey() throws {
        try importKeys(RSA2048.privateKey, RSA2048.publicKey)
        XCTAssert(pgpAgent.isPrepared)
        XCTAssertThrowsError(try basicEncryptDecrypt(using: pgpAgent, keyID: RSA2048.fingerprint)) {
            XCTAssert($0.localizedDescription.contains("gopenpgp: unable to add locked key to a keyring"))
        }
    }

    func testIncompatibleKeyTypes() throws {
        try importKeys(ED25519.publicKey, RSA2048.privateKey)
        XCTAssert(pgpAgent.isPrepared)
        XCTAssertThrowsError(try basicEncryptDecrypt(using: pgpAgent, keyID: ED25519.fingerprint, encryptKeyID: RSA2048.fingerprint)) {
            XCTAssertEqual($0 as! AppError, AppError.KeyExpiredOrIncompatible)
        }
    }

    func testCorruptedKey() throws {
        try importKeys(RSA2048.publicKey.replacingOccurrences(of: "1", with: ""), RSA2048.privateKey)
        XCTAssert(pgpAgent.isPrepared)
        XCTAssertThrowsError(try basicEncryptDecrypt(using: pgpAgent, keyID: RSA2048.fingerprint)) {
            XCTAssert($0.localizedDescription.contains("Can't read keys. Invalid input."))
        }
    }

    func testUnsettKeys() throws {
        try importKeys(ED25519.publicKey, ED25519.privateKey)
        XCTAssert(pgpAgent.isPrepared)
        XCTAssertEqual(try basicEncryptDecrypt(using: pgpAgent, keyID: ED25519.fingerprint), testData)
        keychain.removeContent(for: PgpKey.PUBLIC.getKeychainKey())
        keychain.removeContent(for: PgpKey.PRIVATE.getKeychainKey())
        XCTAssertThrowsError(try basicEncryptDecrypt(using: pgpAgent, keyID: ED25519.fingerprint)) {
            XCTAssertEqual($0 as! AppError, AppError.KeyImport)
        }
    }

    func testNoDecryptionWithIncorrectPassphrase() throws {
        try importKeys(RSA2048.publicKey, RSA2048.privateKey)

        var passphraseRequestCalledCount = 0
        let provideCorrectPassphrase: (String) -> String = { _ in
            passphraseRequestCalledCount = passphraseRequestCalledCount + 1
            return requestPGPKeyPassphrase(keyID: RSA2048.fingerprint)
        }
        let provideIncorrectPassphrase: (String) -> String = { _ in
            passphraseRequestCalledCount = passphraseRequestCalledCount + 1
            return "incorrect passphrase"
        }
        
        // Provide the correct passphrase.
        XCTAssertEqual(try basicEncryptDecrypt(using: pgpAgent, keyID: RSA2048.fingerprint, requestPassphrase: provideCorrectPassphrase), testData)
        XCTAssertEqual(passphraseRequestCalledCount, 1)
        
        // Provide the wrong passphrase.
        XCTAssertThrowsError(try basicEncryptDecrypt(using: pgpAgent, keyID: RSA2048.fingerprint, requestPassphrase: provideIncorrectPassphrase)) {
            XCTAssertEqual($0 as! AppError, AppError.WrongPassphrase)
        }
        XCTAssertEqual(passphraseRequestCalledCount, 2)
        
        // Ask for the passphrase because the previous decryption has failed.
        XCTAssertEqual(try basicEncryptDecrypt(using: pgpAgent, keyID: RSA2048.fingerprint, requestPassphrase: provideCorrectPassphrase), testData)
        XCTAssertEqual(passphraseRequestCalledCount, 3)
    }

    private func importKeys(_ publicKey: String, _ privateKey: String) throws {
        try KeyFileManager(keyType: PgpKey.PUBLIC, keyPath: "", keyHandler: keychain.add).importKey(from: publicKey)
        try KeyFileManager(keyType: PgpKey.PRIVATE, keyPath: "", keyHandler: keychain.add).importKey(from: privateKey)
    }
}


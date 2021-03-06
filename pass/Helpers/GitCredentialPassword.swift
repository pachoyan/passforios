//
//  GitCredentialPassword.swift
//  pass
//
//  Created by Sun, Mingshen on 11/30/19.
//  Copyright © 2019 Bob Sun. All rights reserved.
//

import Foundation
import SVProgressHUD
import passKit

public func requestGitCredentialPassword(credential: GitCredential.Credential,
                                      lastPassword: String?,
                                      controller: UIViewController) -> String? {
    let sem = DispatchSemaphore(value: 0)
    var password: String?
    let message: String = {
        switch credential {
        case .http:
            return "FillInGitAccountPassword.".localize()
        case .ssh:
            return "FillInSshKeyPassphrase.".localize()
        }
    }()

    DispatchQueue.main.async {
        SVProgressHUD.dismiss()
        let alert = UIAlertController(title: "Password".localize(), message: message, preferredStyle: .alert)
        alert.addTextField() {
            $0.text = lastPassword ?? ""
            $0.isSecureTextEntry = true
        }
        alert.addAction(UIAlertAction(title: "Ok".localize(), style: .default) { _ in
            password = alert.textFields?.first?.text
            sem.signal()
        })
        alert.addAction(UIAlertAction(title: "Cancel".localize(), style: .cancel) { _ in
            password = nil
            sem.signal()
        })
        controller.present(alert, animated: true)
    }

    let _ = sem.wait(timeout: .distantFuture)
    return password
}

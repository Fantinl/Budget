import SwiftUI

/// Ouvre le bon éditeur pour une opération : virement → éditeur de virement, sinon formulaire classique.
struct OperationEditor: View {
    let draft: Draft

    var body: some View {
        if let transferID = draft.transaction.transferID, !draft.isNew {
            TransferEditorView(transferID: transferID)
        } else {
            TransactionFormView(draft: draft)
        }
    }
}

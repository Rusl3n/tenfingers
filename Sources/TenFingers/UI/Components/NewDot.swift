import SwiftUI

/// Красный кружок «есть новое»: на кнопках фильтров «Ачивок» и на вкладках «Главной».
struct NewDot: View {
    var body: some View {
        Circle().fill(.red).frame(width: 9, height: 9).accessibilityHidden(true)
    }
}

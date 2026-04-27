import WidgetKit
import SwiftUI

@main
struct EidosWidgetBundle: WidgetBundle {
    var body: some Widget {
        DigestWidget()
        DigestLiveActivity()
        if #available(iOS 18.0, *) {
            EidosTalkControl()
            EidosBriefingControl()
        }
    }
}

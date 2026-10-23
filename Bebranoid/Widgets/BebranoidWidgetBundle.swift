import WidgetKit
import SwiftUI

#if WIDGET_EXTENSION
@main
#endif
struct BebranoidWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        #if os(iOS)
        if #available(iOS 16.2, *) {
            PlaybackLiveActivityWidget()
        }
        #endif
    }
}

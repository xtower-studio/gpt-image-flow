import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 80, height: 80)
                Text("Image Flow").font(.system(size: 26, weight: .semibold))
                Text("버전 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").foregroundStyle(.secondary)
            }
            Text("아이디어에서 다음 시안까지.\n디자이너를 위한 이미지 작업 공간.").multilineTextAlignment(.center).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            BrandCredits()
            Link("도움말 및 업데이트", destination: URL(string: "https://github.com/xtower-studio/gpt-image-flow")!)
                .font(.callout)
        }.padding(32).frame(width: 390)
    }
}

struct BrandCredits: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                brandImage("deaum", width: 58, height: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text("배포 · 비영리단체").font(.caption).foregroundStyle(.secondary)
                    Link("DEAUM · 다음모양", destination: URL(string: "https://deaum.org")!)
                    Text("Daeummoyang").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 14) {
                brandImage("xtower", width: 58, height: 28).padding(.vertical, 7)
                VStack(alignment: .leading, spacing: 4) {
                    Text("디자인 및 개발").font(.caption).foregroundStyle(.secondary)
                    Link("xtower", destination: URL(string: "https://xtower.studio")!)
                }
                Spacer(minLength: 0)
            }
        }
    }
    private func brandImage(_ name: String, width: CGFloat, height: CGFloat) -> some View {
        Group {
            if let url = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "Resources/Brand"), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit()
            }
        }.frame(width: width, height: height).padding(6).background(.white, in: RoundedRectangle(cornerRadius: 8))
    }
}

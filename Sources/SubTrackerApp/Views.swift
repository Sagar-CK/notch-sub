import AppKit
import ServiceManagement
import SubTrackerCore
import SwiftUI

enum Style {
  static let green = Color(red: 0.31, green: 0.48, blue: 0.40)
  static let orange = Color(red: 0.77, green: 0.45, blue: 0.28)
  static let secondary = Color.primary.opacity(0.48)
}

struct ProviderIcon: View {
  let provider: Provider
  var size: CGFloat = 23
  var body: some View {
    if let url = Bundle.main.url(forResource: provider.rawValue, withExtension: "png")
      ?? Bundle.module.url(forResource: provider.rawValue, withExtension: "png"),
      let image = NSImage(contentsOf: url)
    {
      Image(nsImage: image).renderingMode(
        [.claude, .gemini, .antigravity].contains(provider) ? .original : .template
      )
      .resizable().scaledToFit().frame(width: size, height: size).accessibilityLabel(
        provider.title)
    } else {
      Text(provider.title.prefix(1)).font(.system(size: size, weight: .medium))
    }
  }
}

struct TrackerView: View {
  @ObservedObject var store: TrackerStore
  var showSettings: () -> Void
  var width: CGFloat = 382
  @State private var switchingTo: Account?
  var body: some View {
    VStack(spacing: 0) {
      if store.accounts.isEmpty {
        VStack(spacing: 14) {
          Image(systemName: "rectangle.stack").font(.system(size: 28, weight: .light))
            .foregroundStyle(Style.secondary)
          Text(store.refreshing ? "Finding your accounts…" : "No accounts connected").font(
            .system(size: 13))
          if !store.refreshing {
            Button("Connect an account", action: showSettings).buttonStyle(.bordered)
          }
        }.frame(maxWidth: .infinity).frame(height: 200)
      } else {
        ScrollView {
          VStack(spacing: 0) {
            ForEach(Provider.allCases.filter { p in store.accounts.contains { $0.provider == p } })
            { provider in
              ProviderSection(
                provider: provider, accounts: store.accounts.filter { $0.provider == provider },
                busy: store.refreshing || store.switching,
                onSwitch: { switchingTo = $0 }, onSave: { Task { await store.saveClaude() } },
                onConnect: showSettings,
                onLogin: { Task { if await store.prepareLogin(provider) { openLogin(provider) } } })
              if provider != store.accounts.last?.provider {
                Divider().opacity(0.55).padding(.horizontal, 22)
              }
            }
          }
        }.scrollIndicators(.hidden).frame(maxHeight: 540)
      }
      Divider().opacity(0.55)
      HStack {
        Text(store.demo ? "Preview" : store.footer).font(.system(size: 11)).foregroundStyle(
          Style.secondary)
        Spacer()
        if store.refreshing {
          ProgressView().controlSize(.mini).frame(width: 20, height: 20)
        } else {
          Button {
            Task { await store.refresh() }
          } label: {
            Image(systemName: "arrow.clockwise").frame(width: 20, height: 20)
          }.buttonStyle(.plain).help("Refresh usage").accessibilityLabel("Refresh usage")
        }
        Button(action: showSettings) {
          Image(systemName: "slider.horizontal.3").frame(width: 20, height: 20)
        }.buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
        Menu {
          Button("Settings…", action: showSettings)
          Divider()
          Button("Quit Sub Tracker") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        } label: {
          Image(systemName: "ellipsis").frame(width: 24, height: 20)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("More")
      }.padding(.horizontal, 22).padding(.vertical, 10)
    }
    .frame(width: width)
    .background(Color(nsColor: .windowBackgroundColor))
    .alert(
      "Switch to \(switchingTo?.name ?? "account")?",
      isPresented: Binding(get: { switchingTo != nil }, set: { if !$0 { switchingTo = nil } }),
      presenting: switchingTo
    ) { account in
      Button("Switch") {
        Task { await store.activate(account) }
        switchingTo = nil
      }
      Button("Cancel", role: .cancel) { switchingTo = nil }
    } message: { account in
      Text(
        account.provider == .zai
          ? "Updates your existing Z.ai configuration in Claude Code. Restart running clients afterward. ZCode has a separate sign-in."
          : "Updates the local \(account.provider == .codex ? "Codex" : "Claude Code") sign-in. Restart running clients afterward. Desktop app sign-ins may be separate."
      )
    }
    .alert(
      "Sub Tracker",
      isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })
    ) {
      Button("OK") { store.notice = nil }
    } message: {
      Text(store.notice ?? "")
    }
  }
}

struct ProviderSection: View {
  let provider: Provider
  let accounts: [Account]
  let busy: Bool
  let onSwitch: (Account) -> Void
  let onSave: () -> Void
  let onConnect: () -> Void
  let onLogin: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 10) {
        ProviderIcon(provider: provider)
        Text(provider.title).font(.system(size: 15, weight: .semibold))
        Spacer()
        Menu {
          Button("Open usage") { NSWorkspace.shared.open(provider.dashboard) }
          if provider == .claude { Button("Save current sign-in", action: onSave) }
          if provider == .zai { Button("Connect account…", action: onConnect) }
          if provider == .codex { Button("Add account…", action: onLogin) }
          if provider == .claude { Button("Sign in to another account…", action: onLogin) }
          if provider == .gemini || provider == .antigravity {
            Button("Open \(provider.title) CLI…", action: onLogin)
          }
        } label: {
          Image(systemName: "ellipsis").foregroundStyle(Style.secondary).frame(
            width: 20, height: 20)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel(
          "\(provider.title) actions")
      }
      ForEach(accounts) { account in
        if account.isActive || accounts.count == 1 {
          AccountRow(
            account: account, busy: busy, onSwitch: { onSwitch(account) }, onConnect: onConnect)
        } else {
          CompactAccountRow(account: account, busy: busy, onSwitch: { onSwitch(account) })
        }
      }
    }.padding(.horizontal, 22).padding(.vertical, 18)
  }
}

struct CompactAccountRow: View {
  let account: Account
  let busy: Bool
  let onSwitch: () -> Void
  private var window: UsageWindow? {
    account.usage?.windows.first(where: { $0.title == "Weekly" }) ?? account.usage?.windows.first
  }
  private var available: Bool { account.issue == nil && account.usage?.isStale() == false }
  var body: some View {
    HStack(spacing: 12) {
      Text(account.name).font(.system(size: 12)).lineLimit(1)
        .help([account.email, account.planLabel].compactMap { $0 }.joined(separator: " · "))
      Spacer(minLength: 4)
      if available, let window {
        Capsule().fill(Color.primary.opacity(0.065)).frame(width: 40, height: 3)
          .overlay(alignment: .leading) {
            Capsule().fill(Style.green.opacity(0.7)).frame(
              width: 40 * window.remainingPercent / 100, height: 3)
          }
        Text("\(Int(window.remainingPercent))% left").font(.system(size: 10)).monospacedDigit()
          .foregroundStyle(Style.secondary)
          .help("\(window.title)\(window.resetsAt.map { " · resets \($0.formatted())" } ?? "")")
      } else {
        Text(account.issue ?? "Cached").font(.system(size: 10)).foregroundStyle(Style.secondary)
      }
      Button(action: { if account.canSwitch { onSwitch() } else { openProvider(account.provider) } }
      ) {
        Image(systemName: account.canSwitch ? "arrow.left.arrow.right" : "arrow.up.right").font(
          .system(size: 10)
        ).frame(width: 20, height: 18)
      }
      .buttonStyle(.plain).foregroundStyle(Style.secondary).disabled(
        busy || account.issue == "Sign in again"
      )
      .help(
        !account.canSwitch
          ? "Manage this sign-in in \(account.provider.title)"
          : account.issue == "Sign in again"
            ? "Sign in again using the provider menu" : "Make \(account.name) active"
      )
      .accessibilityLabel(
        account.canSwitch ? "Switch to \(account.name)" : "Open \(account.provider.title)")
    }
  }
}

struct AccountRow: View {
  let account: Account
  let busy: Bool
  let onSwitch: () -> Void
  let onConnect: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 7) {
        if account.isActive {
          Circle().fill(Style.green).frame(width: 5, height: 5).help("Active local sign-in")
        }
        Text(account.name).font(.system(size: 12, weight: .medium)).lineLimit(1).help(
          account.email ?? account.name)
        Spacer(minLength: 4)
        if let label = account.planLabel {
          Text(label).font(.system(size: 10)).foregroundStyle(Style.secondary)
        }
        if !account.isActive {
          if account.source == .unavailable {
            Button("Connect", action: onConnect).font(.system(size: 10)).buttonStyle(.plain)
          } else if !account.canSwitch {
            Button(action: { openProvider(account.provider) }) {
              Image(systemName: "arrow.up.right").font(.system(size: 10)).frame(
                width: 20, height: 18)
            }
            .buttonStyle(.plain).help("Manage this sign-in in \(account.provider.title)")
            .accessibilityLabel(
              "Open \(account.provider.title)")
          } else {
            Button(action: onSwitch) {
              Image(systemName: "arrow.left.arrow.right").font(.system(size: 10)).frame(
                width: 20, height: 18)
            }
            .buttonStyle(.plain).foregroundStyle(Style.secondary).disabled(busy)
            .help("Make \(account.name) active").accessibilityLabel("Switch to \(account.name)")
          }
        }
      }
      if let usage = account.usage {
        ForEach(usage.windows) { window in
          WindowRow(window: window, stale: usage.isStale() || account.issue != nil)
        }
        if let spend = usage.spend {
          HStack {
            Text(spend.period)
            Spacer()
            Text(spend.amount, format: .currency(code: spend.currency))
          }
          .font(.system(size: 11)).foregroundStyle(Style.secondary)
        }
        if let credits = usage.creditBalance, credits != "0" {
          Text(creditText(credits)).font(.system(size: 10)).foregroundStyle(Style.secondary)
            .help("Provider-reported credit balance. Credits are not dollars.")
        }
        if usage.isStale(), account.issue == nil {
          Text("Updated \(usage.fetchedAt.formatted(date: .abbreviated, time: .shortened))").font(
            .system(size: 10)
          ).foregroundStyle(Style.secondary)
        }
      }
      if let issue = account.issue {
        HStack(spacing: 5) {
          Image(systemName: "exclamationmark.circle").font(.system(size: 10))
          Text(issue).font(.system(size: 10))
          Spacer()
          Button {
            NSWorkspace.shared.open(account.provider.dashboard)
          } label: {
            Image(systemName: "arrow.up.right").font(.system(size: 9))
          }.buttonStyle(.plain).help("Open provider usage")
        }.foregroundStyle(Style.orange)
      } else if account.usage == nil {
        Text("Loading…").font(.system(size: 11)).foregroundStyle(Style.secondary)
      }
    }
  }
  private func creditText(_ value: String) -> String {
    if let n = Double(value) {
      return "\(n.formatted(.number.precision(.fractionLength(0)))) credits"
    }
    return "\(value) credits"
  }
}

struct WindowRow: View {
  let window: UsageWindow
  let stale: Bool
  var color: Color {
    stale
      ? .secondary
      : window.remainingPercent <= 10
        ? .red.opacity(0.7) : window.remainingPercent <= 25 ? Style.orange : Style.green
  }
  var body: some View {
    VStack(spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        Text(window.title).foregroundStyle(Style.secondary)
        Spacer()
        Text(
          window.hasReset()
            ? "Awaiting refresh"
            : "\(Int(window.remainingPercent.rounded(.down)))% left\(stale ? " · cached" : "")"
        )
        .foregroundStyle(window.hasReset() ? Style.secondary : Color.primary.opacity(0.8))
        .monospacedDigit()
      }.font(.system(size: 11))
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.primary.opacity(0.065))
          Capsule().fill(color).frame(
            width: max(0, geo.size.width * (window.hasReset() ? 0 : window.remainingPercent / 100)))
        }
      }.frame(height: 3)
      if let reset = window.resetsAt, !window.hasReset() {
        HStack {
          if let used = window.used, let limit = window.limit {
            Text(
              "\(used.formatted(.number.precision(.fractionLength(0)))) / \(limit.formatted(.number.precision(.fractionLength(0))))\(window.unit.map { " \($0)" } ?? "")"
            )
          }
          Spacer()
          Text("Resets \(reset.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
        }.font(.system(size: 9)).foregroundStyle(Style.secondary.opacity(0.85))
      }
    }.accessibilityElement(children: .combine)
      .help(
        "\(window.usedPercent.formatted())% used\(window.resetsAt.map { ", resets \($0.formatted())" } ?? "")"
      )
  }
}

struct SettingsView: View {
  @ObservedObject var store: TrackerStore
  @AppStorage("showRemaining") var showRemaining = true
  @AppStorage("placement") var placement = Placement.notch.rawValue
  @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
  @State private var name = ""
  @State private var key = ""
  @State private var host = "api.z.ai"
  @State private var connecting = false
  @State private var connectionError: String?
  @State private var addingZai = false
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Text("Placement")
        Spacer()
        Picker("Placement", selection: $placement) {
          ForEach(Placement.allCases) { option in Text(option.title).tag(option.rawValue) }
        }.labelsHidden().pickerStyle(.segmented).frame(width: 230)
          .onChange(of: placement) { _, _ in store.changed?() }
      }
      VStack(spacing: 16) {
        if placement != Placement.notch.rawValue {
          HStack {
            Text("Menu bar percentage")
            Spacer()
            Toggle("Menu bar percentage", isOn: $showRemaining).labelsHidden()
          }.onChange(of: showRemaining) { _, _ in store.changed?() }
        }
        HStack {
          Text("Open at login")
          Spacer()
          Toggle("Open at login", isOn: $launchAtLogin).labelsHidden()
        }.onChange(of: launchAtLogin) { _, value in
          do {
            if value {
              try SMAppService.mainApp.register()
            } else {
              try SMAppService.mainApp.unregister()
            }
          } catch {
            connectionError = "Login item could not be changed."
            launchAtLogin = SMAppService.mainApp.status == .enabled
          }
        }
      }.toggleStyle(.switch).controlSize(.small)
      Divider()
      HStack {
        ProviderIcon(provider: .claude)
        Text("Claude").fontWeight(.medium)
        Spacer()
        Button("Save account") { Task { await store.saveClaude() } }.help(
          "Save the current Claude Code sign-in in Keychain")
      }
      HStack(spacing: 10) {
        ProviderIcon(provider: .zai)
        Text("Z.ai").fontWeight(.medium)
        Spacer()
        Button(addingZai ? "Cancel" : "Connect") {
          addingZai.toggle()
          key = ""
          connectionError = nil
        }
      }
      if addingZai {
        VStack(spacing: 10) {
          TextField("Account name", text: $name)
          SecureField("Coding Plan API key", text: $key)
          HStack {
            Picker("Provider", selection: $host) {
              Text("Z.ai").tag("api.z.ai")
              Text("BigModel").tag("open.bigmodel.cn")
            }.labelsHidden().frame(width: 150)
            Spacer()
            if connecting { ProgressView().controlSize(.small) }
            Button("Connect") {
              connecting = true
              connectionError = nil
              Task {
                if await store.connectZai(name: name, token: key, host: host) {
                  key = ""
                  name = ""
                  addingZai = false
                } else {
                  connectionError = store.notice
                  store.notice = nil
                }
                connecting = false
              }
            }.disabled(key.isEmpty || connecting)
          }
        }.textFieldStyle(.roundedBorder)
      }
      if let connectionError {
        Text(connectionError).font(.system(size: 11)).foregroundStyle(Style.orange)
      }
      Divider()
      HStack {
        Button {
          Task { await store.refresh() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }.buttonStyle(.plain).help("Refresh accounts · automatically updates every five minutes")
        Spacer()
        Button("Quit") { NSApplication.shared.terminate(nil) }
      }
    }.font(.system(size: 12)).controlSize(.small).padding(24).frame(width: 410)
      .background(Color(nsColor: .windowBackgroundColor))
      .alert(
        "Sub Tracker",
        isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })
      ) {
        Button("OK") { store.notice = nil }
      } message: {
        Text(store.notice ?? "")
      }
  }
}

func openZCode() {
  let candidates = [
    URL(fileURLWithPath: "/Applications/ZCode.app"),
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Applications/ZCode.app"),
  ]
  if let app = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
    NSWorkspace.shared.open(app)
  } else {
    NSWorkspace.shared.open(Provider.zai.dashboard)
  }
}

func openLogin(_ provider: Provider) {
  // Opening a .command file avoids Apple Events permission and never interpolates user text.
  let command: String
  switch provider {
  case .codex: command = "codex login"
  case .claude: command = "claude auth login"
  case .gemini: command = "gemini"
  case .antigravity:
    guard
      let executable = AntigravityUsage.executable(
        home: FileManager.default.homeDirectoryForCurrentUser,
        environment: ProcessInfo.processInfo.environment)
    else {
      NSWorkspace.shared.open(provider.dashboard)
      return
    }
    command = "'" + executable.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
  case .zai:
    openZCode()
    return
  }
  let text =
    "#!/bin/zsh\nexport PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\"\n\(command)\n"
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(
    "subtracker-\(provider.rawValue)-login.command")
  do {
    try Data(text.utf8).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    NSWorkspace.shared.open(url)
  } catch { NSSound.beep() }
}

func openProvider(_ provider: Provider) {
  if provider == .zai { openZCode() } else { openLogin(provider) }
}

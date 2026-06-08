//
//  LoginView.swift
//  MyFavor
//
//  登录页 — 邮箱 Magic Link
//

import SwiftUI

@MainActor
struct LoginView: View {
    @State private var auth  = AuthService.shared
    @State private var magic = MagicLinkService.shared

    /// 「先逛逛」回调
    var onSkip: (() -> Void)? = nil
    
    /// 当前登录阶段
    private enum Stage {
        case email     // 输入邮箱阶段
        case code      // 输入 6 位验证码阶段
    }
    @State private var stage: Stage = .email
    @State private var email: String = ""
    @State private var code: String = ""
    @FocusState private var emailFocused: Bool
    @FocusState private var codeFocused: Bool
    
    var body: some View {
        ZStack {
            BrandGradient().ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Logo 区
                logoHeader
                    .padding(.top, 40)
                
                Spacer()
                
                // 主内容卡片
                VStack(spacing: 18) {
                    switch stage {
                    case .email: emailInputCard
                    case .code:  codeInputCard
                    }
                }
                .padding(.horizontal, 22)
                .animation(.spring(response: 0.35), value: stage)
                
                Spacer()
                
                // 底部链接
                bottomLinks
                    .padding(.bottom, 30)
            }
        }
        .onTapGesture {
            emailFocused = false
            codeFocused = false
        }
        .onAppear { emailFocused = true }
    }
    
    // MARK: - Logo
    private var logoHeader: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 32)
                    .fill(.white.opacity(0.18))
                    .frame(width: 100, height: 100)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.white)
            }
            Text("MyFavor")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("自托管 · 你的数据你做主")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
    }
    
    // MARK: - 阶段 1:输入邮箱
    private var emailInputCard: some View {
        VStack(spacing: 14) {
            // 错误提示
            if let msg = magic.errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.28))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .transition(.scale.combined(with: .opacity))
            }
            
            // 邮箱输入框
            HStack(spacing: 10) {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(.white.opacity(0.7))
                TextField("", text: $email, prompt: Text("输入邮箱").foregroundStyle(.white.opacity(0.6)))
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused($emailFocused)
                    .submitLabel(.send)
                    .onSubmit { Task { await sendCode() } }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(.white.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // 发送按钮
            Button { Task { await sendCode() } } label: {
                HStack {
                    if magic.isLoading {
                        ProgressView().tint(.brandInk)
                    } else {
                        Text("发送验证码")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.white)
                .foregroundStyle(.brandInk)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(magic.isLoading || !isValidEmail(email))
            .opacity((!magic.isLoading && isValidEmail(email)) ? 1 : 0.6)
        }
    }


    // MARK: - 阶段 2:输入 6 位验证码
    private var codeInputCard: some View {
        VStack(spacing: 14) {
            // 顶部说明
            VStack(spacing: 6) {
                Text("验证码已发送到")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                Text(email)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            }
            
            // 错误提示
            if let msg = magic.errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.28))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            // 6 位验证码输入(隐藏文本框 + 6 个格子展示)
            ZStack {
                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($codeFocused)
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .onChange(of: code) { _, newValue in
                        // 仅保留数字,最多 6 位
                        let cleaned = newValue.filter { $0.isNumber }.prefix(6)
                        if String(cleaned) != newValue { code = String(cleaned) }
                        // 满 6 位自动验证
                        if cleaned.count == 6 {
                            Task { await verifyCode() }
                        }
                    }
                
                HStack(spacing: 10) {
                    ForEach(0..<6, id: \.self) { i in
                        codeDigitCell(at: i)
                    }
                }
                .onTapGesture { codeFocused = true }
            }
            
            // Loading
            if magic.isLoading {
                ProgressView().tint(.white).padding(.top, 4)
            }
            
            // 重发
            HStack {
                Button {
                    stage = .email
                    code = ""
                    magic.errorMessage = nil
                } label: {
                    Label("换个邮箱", systemImage: "chevron.left")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                if magic.resendCountdown > 0 {
                    Text("\(magic.resendCountdown)s 后可重发")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Button {
                        Task { await sendCode() }
                    } label: {
                        Text("重新发送")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.top, 6)
        }
        .onAppear { codeFocused = true }
    }
    
    private func codeDigitCell(at i: Int) -> some View {
        let chars = Array(code)
        let char = i < chars.count ? String(chars[i]) : ""
        let isFilled = !char.isEmpty
        let isCurrent = i == code.count
        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(isFilled ? 0.95 : 0.18))
                .frame(width: 44, height: 54)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white, lineWidth: isCurrent ? 2 : 0)
                )
            Text(char)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(isFilled ? .brandInk : .white)
        }
    }
    
    // MARK: - 底部链接
    private var bottomLinks: some View {
        VStack(spacing: 14) {
            if let onSkip = onSkip {
                Button("先在本地使用") { onSkip() }
                    .font(.subheadline.bold())
                    .foregroundStyle(.white.opacity(0.9))
            }
            Text("登录后数据将自动加密同步至云端")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
    
    // MARK: - 业务方法
    private func sendCode() async {
        guard isValidEmail(email) else { return }
        let ok = await magic.sendCode(to: email)
        if ok { stage = .code }
    }
    
    private func verifyCode() async {
        guard code.count == 6 else { return }
        let ok = await magic.verifyCode(email: email, code: code)
        if !ok {
            code = ""   // 失败清空,方便重输
        }
    }
    
    private func isValidEmail(_ s: String) -> Bool {
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return s.range(of: pattern, options: .regularExpression) != nil
    }
}

#Preview { LoginView() }

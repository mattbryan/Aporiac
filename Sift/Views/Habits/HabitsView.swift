import SwiftUI

struct HabitsView: View {
    var body: some View {
        VStack {
            Text("Habits")
                .font(.siftTitle)
                .foregroundStyle(Color.siftInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, DS.Spacing.lg)

            Spacer()
        }
        .background(Color.siftSurface.ignoresSafeArea())
    }
}

#Preview {
    HabitsView()
}

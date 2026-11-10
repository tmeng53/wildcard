#if os(iOS)
import CheckInDomain
import Contracts

/// 一起练 on the compose page: the squadmates a 训练 was done with, and the hints that pick them.
extension ComposeModel {
    /// Whether the post goes to a squad, so 一起练 can name anyone in it: a new post while shared,
    /// an edit of one that went to a squad.
    var goesToSquad: Bool {
        switch purpose {
        case .new(let squad): squad != nil && isShared
        case .edit(let checkIn): !checkIn.audience.isOnlyMe
        }
    }

    /// What 一起练 offers now: the squadmates and those who trained around the same time. None for
    /// a post kept to the member or other than a 训练, so the row hides.
    var together: TrainingTogether {
        guard kind == .trained, goesToSquad else { return .none }
        return offer(day, workout, workout == nil ? startTime : nil)
    }

    /// The squadmates picked who are still in the squad, once it is known: one who left isn't
    /// on the row to be let go, so they aren't posted (the API would refuse a new post naming
    /// them) and don't count toward the limit.
    var pickedMates: [MemberID] {
        let mates = Set(together.mates.map(\.member))
        return mates.isEmpty ? trainedWith : trainedWith.filter(mates.contains)
    }

    /// Names a squadmate on the 训练, or lets them go again; at most `TrainedWith.limit`.
    func toggle(mate: MemberID) {
        if let index = trainedWith.firstIndex(of: mate) {
            trainedWith.remove(at: index)
        } else if pickedMates.count < TrainedWith.limit {
            trainedWith.append(mate)
        }
    }

    /// Takes a hint at a tap: names its squadmate, and when they named the member, starts the 训练
    /// from theirs (sport, start and minutes) unless a Health workout is picked, whose own numbers
    /// stay. Tapping it again lets the squadmate go; the 训练's fields stay.
    func take(_ hint: TrainingTogether.Hint) {
        let picking = !trainedWith.contains(hint.mate)
        toggle(mate: hint.mate)
        guard picking, trainedWith.contains(hint.mate), hint.namedMe, workout == nil, !isEditing else { return }
        activity = hint.activity
        startTime = hint.startTime
        minutes = hint.minutes
    }
}
#endif

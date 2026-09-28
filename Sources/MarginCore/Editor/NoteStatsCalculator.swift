/// Counts behind `NoteStats` for one body of text.
public enum NoteStatsCalculator {
    /// Words (runs of non-whitespace), and open/total tasks outside code.
    public static func count(body: String) -> (words: Int, openTasks: Int, totalTasks: Int) {
        let tasks = MarkdownScanner().scan(body).tasks
        return (NoteIndex.wordCount(body), tasks.lazy.filter { !$0.done }.count, tasks.count)
    }
}

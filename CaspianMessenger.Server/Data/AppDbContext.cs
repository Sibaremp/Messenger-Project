using CaspianMessenger.Server.Models;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Data;

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<Chat> Chats => Set<Chat>();
    public DbSet<ChatMember> ChatMembers => Set<ChatMember>();
    public DbSet<Message> Messages => Set<Message>();
    public DbSet<Comment> Comments => Set<Comment>();
    public DbSet<Attachment> Attachments => Set<Attachment>();
    public DbSet<MessageReadStatus> MessageReadStatuses => Set<MessageReadStatus>();
    public DbSet<Poll> Polls => Set<Poll>();
    public DbSet<PollOption> PollOptions => Set<PollOption>();
    public DbSet<PollVote> PollVotes => Set<PollVote>();
    public DbSet<Mention> Mentions => Set<Mention>();
    public DbSet<Session> Sessions => Set<Session>();
    public DbSet<Call> Calls => Set<Call>();
    public DbSet<CallParticipant> CallParticipants => Set<CallParticipant>();
    public DbSet<UserDevice> UserDevices => Set<UserDevice>();
    public DbSet<Person> People => Set<Person>();
    public DbSet<Admin> Admins => Set<Admin>();
    public DbSet<Subject> Subjects => Set<Subject>();
    public DbSet<TeacherSubjectGroup> TeacherSubjectGroups => Set<TeacherSubjectGroup>();
    public DbSet<Notification> Notifications => Set<Notification>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // User — Seq is a GENERATED ALWAYS AS IDENTITY column (auto-increment int)
        modelBuilder.Entity<User>()
            .Property(u => u.Seq)
            .UseIdentityAlwaysColumn();
        modelBuilder.Entity<User>()
            .HasIndex(u => u.Name).IsUnique();
        modelBuilder.Entity<User>()
            .HasIndex(u => u.Phone);
        modelBuilder.Entity<User>()
            .HasIndex(u => u.Group);

        // Chat
        modelBuilder.Entity<Chat>()
            .HasIndex(c => c.Type);
        modelBuilder.Entity<Chat>()
            .HasIndex(c => c.IsAcademic);
        modelBuilder.Entity<Chat>()
            .HasOne(c => c.Admin)
            .WithMany()
            .HasForeignKey(c => c.AdminId)
            .OnDelete(DeleteBehavior.SetNull);

        // ChatMember
        modelBuilder.Entity<ChatMember>()
            .HasIndex(cm => new { cm.ChatId, cm.UserId }).IsUnique();
        modelBuilder.Entity<ChatMember>()
            .HasIndex(cm => cm.UserId);
        modelBuilder.Entity<ChatMember>()
            .HasOne(cm => cm.Chat)
            .WithMany(c => c.Members)
            .HasForeignKey(cm => cm.ChatId)
            .OnDelete(DeleteBehavior.Cascade);
        modelBuilder.Entity<ChatMember>()
            .HasOne(cm => cm.User)
            .WithMany(u => u.ChatMemberships)
            .HasForeignKey(cm => cm.UserId)
            .OnDelete(DeleteBehavior.Cascade);

        // Message
        modelBuilder.Entity<Message>()
            .HasIndex(m => new { m.ChatId, m.CreatedAt });
        modelBuilder.Entity<Message>()
            .HasIndex(m => m.SenderId);
        modelBuilder.Entity<Message>()
            .HasIndex(m => m.ReplyToId);
        modelBuilder.Entity<Message>()
            .HasOne(m => m.Chat)
            .WithMany(c => c.Messages)
            .HasForeignKey(m => m.ChatId)
            .OnDelete(DeleteBehavior.Cascade);
        modelBuilder.Entity<Message>()
            .HasOne(m => m.Sender)
            .WithMany(u => u.Messages)
            .HasForeignKey(m => m.SenderId)
            .OnDelete(DeleteBehavior.Restrict);
        modelBuilder.Entity<Message>()
            .HasOne(m => m.ReplyTo)
            .WithMany()
            .HasForeignKey(m => m.ReplyToId)
            .OnDelete(DeleteBehavior.SetNull);

        // Comment
        modelBuilder.Entity<Comment>()
            .HasIndex(c => new { c.MessageId, c.CreatedAt });
        modelBuilder.Entity<Comment>()
            .HasIndex(c => c.SenderId);
        modelBuilder.Entity<Comment>()
            .HasOne(c => c.Message)
            .WithMany(m => m.Comments)
            .HasForeignKey(c => c.MessageId)
            .OnDelete(DeleteBehavior.Cascade);
        modelBuilder.Entity<Comment>()
            .HasOne(c => c.Sender)
            .WithMany(u => u.Comments)
            .HasForeignKey(c => c.SenderId)
            .OnDelete(DeleteBehavior.Restrict);
        modelBuilder.Entity<Comment>()
            .HasOne(c => c.ReplyTo)
            .WithMany()
            .HasForeignKey(c => c.ReplyToId)
            .OnDelete(DeleteBehavior.SetNull);

        // Attachment
        modelBuilder.Entity<Attachment>()
            .HasIndex(a => a.MessageId);
        modelBuilder.Entity<Attachment>()
            .HasIndex(a => a.CommentId);
        modelBuilder.Entity<Attachment>()
            .HasIndex(a => a.Type);
        modelBuilder.Entity<Attachment>()
            .HasOne(a => a.Message)
            .WithMany(m => m.Attachments)
            .HasForeignKey(a => a.MessageId)
            .OnDelete(DeleteBehavior.Cascade);
        modelBuilder.Entity<Attachment>()
            .HasOne(a => a.Comment)
            .WithMany(c => c.Attachments)
            .HasForeignKey(a => a.CommentId)
            .OnDelete(DeleteBehavior.Cascade);

        // MessageReadStatus
        modelBuilder.Entity<MessageReadStatus>()
            .HasIndex(r => new { r.MessageId, r.UserId }).IsUnique();
        modelBuilder.Entity<MessageReadStatus>()
            .HasOne(r => r.Message)
            .WithMany(m => m.ReadStatuses)
            .HasForeignKey(r => r.MessageId)
            .OnDelete(DeleteBehavior.Cascade);
        modelBuilder.Entity<MessageReadStatus>()
            .HasOne(r => r.User)
            .WithMany(u => u.ReadStatuses)
            .HasForeignKey(r => r.UserId)
            .OnDelete(DeleteBehavior.Cascade);

        // Poll
        modelBuilder.Entity<Poll>().HasIndex(p => p.IsClosed);
        modelBuilder.Entity<Poll>().HasIndex(p => p.Deadline);

        // PollOption
        modelBuilder.Entity<PollOption>()
            .HasOne(o => o.Poll).WithMany(p => p.Options)
            .HasForeignKey(o => o.PollId).OnDelete(DeleteBehavior.Cascade);
        modelBuilder.Entity<PollOption>().HasIndex(o => o.PollId);

        // PollVote
        modelBuilder.Entity<PollVote>()
            .HasIndex(v => new { v.PollId, v.OptionId, v.UserId }).IsUnique();
        modelBuilder.Entity<PollVote>()
            .HasOne(v => v.Poll).WithMany(p => p.Votes)
            .HasForeignKey(v => v.PollId).OnDelete(DeleteBehavior.Cascade);
        modelBuilder.Entity<PollVote>()
            .HasOne(v => v.Option).WithMany(o => o.Votes)
            .HasForeignKey(v => v.OptionId).OnDelete(DeleteBehavior.Cascade);

        // Mention
        modelBuilder.Entity<Mention>()
            .HasOne(m => m.Message).WithMany(msg => msg.Mentions)
            .HasForeignKey(m => m.MessageId).OnDelete(DeleteBehavior.Cascade);
        modelBuilder.Entity<Mention>().HasIndex(m => m.MessageId);
        modelBuilder.Entity<Mention>().HasIndex(m => m.UserId);

        // Message — Poll relationship
        modelBuilder.Entity<Message>()
            .HasOne(m => m.Poll).WithMany()
            .HasForeignKey(m => m.PollId).OnDelete(DeleteBehavior.SetNull);

        // Chat — PinnedMessageIds as JSON column
        modelBuilder.Entity<Chat>()
            .Property(c => c.PinnedMessageIds)
            .HasColumnType("jsonb");

        // Session
        modelBuilder.Entity<Session>()
            .HasOne(s => s.User).WithMany(u => u.Sessions)
            .HasForeignKey(s => s.UserId).OnDelete(DeleteBehavior.Cascade);
        modelBuilder.Entity<Session>().HasIndex(s => s.TokenHash).IsUnique();
        modelBuilder.Entity<Session>().HasIndex(s => s.UserId);
        modelBuilder.Entity<Session>().HasIndex(s => new { s.LastActivity, s.IsActive });

        // UserDevice
        modelBuilder.Entity<UserDevice>()
            .HasOne(d => d.User).WithMany(u => u.Devices)
            .HasForeignKey(d => d.UserId).OnDelete(DeleteBehavior.Cascade);
        modelBuilder.Entity<UserDevice>().HasIndex(d => d.FcmToken).IsUnique();
        modelBuilder.Entity<UserDevice>().HasIndex(d => d.UserId);

        // Admin
        modelBuilder.Entity<Admin>().HasIndex(a => a.Login).IsUnique();

        // Person
        modelBuilder.Entity<Person>()
            .HasIndex(p => new { p.LastName, p.FirstName, p.MiddleName });
        modelBuilder.Entity<Person>()
            .HasIndex(p => p.Role);
        modelBuilder.Entity<Person>()
            .HasOne(p => p.User).WithMany()
            .HasForeignKey(p => p.UserId).OnDelete(DeleteBehavior.SetNull);

        // Subject
        modelBuilder.Entity<Subject>()
            .HasIndex(s => s.Name).IsUnique();

        // TeacherSubjectGroup
        modelBuilder.Entity<TeacherSubjectGroup>()
            .HasIndex(t => new { t.PersonId, t.SubjectId, t.GroupName }).IsUnique();
        modelBuilder.Entity<TeacherSubjectGroup>()
            .HasOne(t => t.Subject).WithMany(s => s.Assignments)
            .HasForeignKey(t => t.SubjectId).OnDelete(DeleteBehavior.Cascade);
        modelBuilder.Entity<TeacherSubjectGroup>()
            .HasOne(t => t.Person).WithMany()
            .HasForeignKey(t => t.PersonId).OnDelete(DeleteBehavior.Cascade);
        modelBuilder.Entity<TeacherSubjectGroup>()
            .HasIndex(t => t.PersonId);
        modelBuilder.Entity<TeacherSubjectGroup>()
            .HasIndex(t => t.GroupName);

        // Notification
        modelBuilder.Entity<Notification>()
            .HasIndex(n => n.SentAt);
        modelBuilder.Entity<Notification>()
            .HasIndex(n => n.Target);

        // Call
        modelBuilder.Entity<Call>().HasIndex(c => c.State);
        modelBuilder.Entity<CallParticipant>()
            .HasOne(cp => cp.Call).WithMany(c => c.Participants)
            .HasForeignKey(cp => cp.CallId).OnDelete(DeleteBehavior.Cascade);
        modelBuilder.Entity<CallParticipant>().HasIndex(cp => cp.CallId);
        modelBuilder.Entity<CallParticipant>().HasIndex(cp => cp.UserId);
    }
}

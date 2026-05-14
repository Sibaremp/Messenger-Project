using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CaspianMessenger.Server.Migrations
{
    /// <inheritdoc />
    public partial class AddMessagePostAsCommunity : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "PostAsCommunity",
                table: "Messages",
                type: "boolean",
                nullable: false,
                defaultValue: false);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "PostAsCommunity",
                table: "Messages");
        }
    }
}

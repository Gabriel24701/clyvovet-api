using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ClyvoVet.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddPhoneAndAddressToUser : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "Users",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "RAW(16)", nullable: false),
                    Name = table.Column<string>(type: "NVARCHAR2(100)", maxLength: 100, nullable: false),
                    Email = table.Column<string>(type: "NVARCHAR2(2000)", nullable: false),
                    Password = table.Column<string>(type: "NVARCHAR2(2000)", nullable: false),
                    Phone = table.Column<string>(type: "NVARCHAR2(20)", maxLength: 20, nullable: false),
                    Address = table.Column<string>(type: "NVARCHAR2(200)", maxLength: 200, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Users", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Pets",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "RAW(16)", nullable: false),
                    Name = table.Column<string>(type: "NVARCHAR2(2000)", nullable: false),
                    Species = table.Column<string>(type: "NVARCHAR2(2000)", nullable: false),
                    Breed = table.Column<string>(type: "NVARCHAR2(2000)", nullable: false),
                    Weight = table.Column<double>(type: "BINARY_DOUBLE", nullable: false),
                    Color = table.Column<string>(type: "NVARCHAR2(2000)", nullable: false),
                    NextCheckup = table.Column<DateTime>(type: "TIMESTAMP(7)", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "TIMESTAMP(7)", nullable: false),
                    OwnerId = table.Column<Guid>(type: "RAW(16)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Pets", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Pets_Users_OwnerId",
                        column: x => x.OwnerId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Pets_OwnerId",
                table: "Pets",
                column: "OwnerId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "Pets");

            migrationBuilder.DropTable(
                name: "Users");
        }
    }
}

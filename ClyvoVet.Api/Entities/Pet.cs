using System;
using System.Collections.Generic;

namespace ClyvoVet.Api.Models
{
    public class Pet
    {
        public Guid Id { get; set; } = Guid.NewGuid();
        public string Name { get; set; } = string.Empty;
        public string Species { get; set; } = string.Empty;
        public string Breed { get; set; } = string.Empty;
        public double Weight { get; set; }
        public string Color { get; set; } = string.Empty;
        public DateTime NextCheckup { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        // Foreign Key
        public Guid OwnerId { get; set; }
        public User Owner { get; set; } = null!;
        
        // public ICollection<Vaccine> Vaccines { get; set; } = new List<Vaccine>();
        // public ICollection<Medication> Medications { get; set; } = new List<Medication>();
    }
}
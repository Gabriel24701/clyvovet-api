using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ClyvoVet.Api.Data;
using ClyvoVet.Api.Models;

namespace ClyvoVet.Api.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class PetsController : ControllerBase
    {
        private readonly AppDbContext _context;

        public PetsController(AppDbContext context)
        {
            _context = context;
        }

        // POST: api/pets
        [HttpPost]
        public async Task<ActionResult<Pet>> CreatePet(Pet pet)
        {
            _context.Pets.Add(pet);
            await _context.SaveChangesAsync();
            return CreatedAtAction(nameof(GetPetById), new { id = pet.Id }, pet);
        }

        // GET: api/pets
        [HttpGet]
        public async Task<ActionResult<IEnumerable<Pet>>> GetAllPets()
        {
            return await _context.Pets.ToListAsync();
        }
        
        // GET: api/pets/{id}
        [HttpGet("{id}")]
        public async Task<ActionResult<Pet>> GetPetById(Guid id)
        {
            var pet = await _context.Pets.FindAsync(id);
            if (pet == null) return NotFound();
            return pet;
        }
        
        // GET: api/pets/owner/{ownerId}
        [HttpGet("owner/{ownerId}")]
        public async Task<ActionResult<IEnumerable<Pet>>> GetPetsByOwner(Guid ownerId)
        {
            var pets = await _context.Pets.Where(p => p.OwnerId == ownerId).ToListAsync();
            return pets;
        }
        
        // GET: api/pets/species/{species}
        [HttpGet("species/{species}")]
        public async Task<ActionResult<IEnumerable<Pet>>> GetPetsBySpecies(string species)
        {
            var pets = await _context.Pets.Where(p => p.Species.ToLower() == species.ToLower()).ToListAsync();
            return pets;
        }

        // PUT: api/pets/{id}
        [HttpPut("{id}")]
        public async Task<IActionResult> UpdatePet(Guid id, Pet pet)
        {
            if (id != pet.Id) return BadRequest();

            _context.Entry(pet).State = EntityState.Modified;
            await _context.SaveChangesAsync();

            return NoContent();
        }

        // DELETE: api/pets/{id}
        [HttpDelete("{id}")]
        public async Task<IActionResult> DeletePet(Guid id)
        {
            var pet = await _context.Pets.FindAsync(id);
            if (pet == null) return NotFound();

            _context.Pets.Remove(pet);
            await _context.SaveChangesAsync();

            return NoContent();
        }
    }
}
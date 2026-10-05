// Read-only verification harness linked to the pinned local Core3/Engine3 build.
// No zone server or character database is opened.
#include "engine/engine.h"
#include "terrain/ProceduralTerrainAppearance.h"
#include <fstream>
#include <iostream>
#include <iomanip>
#include <vector>
int main(int argc, char **argv) {
    if (argc != 2) { std::cerr << "usage: core3_height_reference original.trn < coordinates.tsv\n"; return 2; }
    try {
        std::ifstream input(argv[1], std::ios::binary);
        std::vector<unsigned char> bytes((std::istreambuf_iterator<char>(input)), {});
        if (bytes.empty()) return 2;
        IffStream iff;
        if (!iff.parseChunks(bytes.data(), int(bytes.size()), argv[1])) return 3;
        ProceduralTerrainAppearance terrain;
        terrain.load(&iff);
        float x, z;
        std::cout << std::setprecision(10);
        while (std::cin >> x >> z) std::cout << "HEIGHT\t" << x << '\t' << z << '\t' << terrain.getHeight(x, z) << '\n';
    } catch (const Exception &e) { std::cerr << e.getMessage().toCharArray() << '\n'; return 1; }
    return 0;
}

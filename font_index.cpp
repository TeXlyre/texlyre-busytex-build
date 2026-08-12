#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

extern "C" char *kpse_find_file(const char *name, int format, int must_exist);

namespace {

const char FONT_INDEX_NAME[] = "busytex-fontindex.txt";
const char FONT_INDEX_HEADER[] = "busytex-fontindex 1";
const int FONT_INDEX_TEX_FORMAT = 26;
const int FONT_INDEX_FIELDS = 17;

struct Record {
    std::string file;
    std::string psname;
    int face;
    int weight;
    int width;
    int slant;
    int is_regular;
    int is_bold;
    int is_italic;
    double design_size;
    double min_size;
    double max_size;
    int subfamily_id;
    int name_code;
    std::vector<std::string> names[3];
};

std::vector<Record> records;
int state = 0;

std::vector<std::string> split(const std::string &value, char separator)
{
    std::vector<std::string> parts;
    std::string::size_type begin = 0;

    while (true) {
        std::string::size_type end = value.find(separator, begin);
        if (end == std::string::npos) {
            parts.push_back(value.substr(begin));
            break;
        }
        parts.push_back(value.substr(begin, end - begin));
        begin = end + 1;
    }

    return parts;
}

std::vector<std::string> split_names(const std::string &value)
{
    if (value.empty())
        return std::vector<std::string>();
    return split(value, '|');
}

bool parse(const std::string &line, Record &record)
{
    std::vector<std::string> fields = split(line, '\t');
    if (fields.size() != (size_t) FONT_INDEX_FIELDS || fields[0].empty() || fields[2].empty())
        return false;

    record.file = fields[0];
    record.face = atoi(fields[1].c_str());
    record.psname = fields[2];
    record.weight = atoi(fields[3].c_str());
    record.width = atoi(fields[4].c_str());
    record.slant = atoi(fields[5].c_str());
    record.is_regular = atoi(fields[6].c_str());
    record.is_bold = atoi(fields[7].c_str());
    record.is_italic = atoi(fields[8].c_str());
    record.design_size = atof(fields[9].c_str());
    record.min_size = atof(fields[10].c_str());
    record.max_size = atof(fields[11].c_str());
    record.subfamily_id = atoi(fields[12].c_str());
    record.name_code = atoi(fields[13].c_str());
    record.names[0] = split_names(fields[14]);
    record.names[1] = split_names(fields[15]);
    record.names[2] = split_names(fields[16]);

    return !record.names[0].empty();
}

bool read_index(const char *path)
{
    FILE *file = fopen(path, "r");
    if (file == NULL)
        return false;

    std::string content;
    char buffer[16384];
    size_t got;
    while ((got = fread(buffer, 1, sizeof(buffer), file)) > 0)
        content.append(buffer, got);
    fclose(file);

    std::vector<std::string> lines = split(content, '\n');
    if (lines.empty()
        || lines[0].compare(0, sizeof(FONT_INDEX_HEADER) - 1, FONT_INDEX_HEADER) != 0)
        return false;

    records.reserve(lines.size());
    for (size_t i = 1; i < lines.size(); ++i) {
        if (lines[i].empty())
            continue;
        Record record;
        if (parse(lines[i], record))
            records.push_back(record);
    }

    return !records.empty();
}

}

extern "C" int busytex_font_index_load(void)
{
    if (state != 0)
        return state > 0;

    state = -1;
    char *path = kpse_find_file(FONT_INDEX_NAME, FONT_INDEX_TEX_FORMAT, 0);
    if (path == NULL)
        return 0;

    if (read_index(path))
        state = 1;
    free(path);

    return state > 0;
}

extern "C" int busytex_font_index_count(void)
{
    return (int) records.size();
}

extern "C" const char *busytex_font_index_file(int entry)
{
    return records[entry].file.c_str();
}

extern "C" int busytex_font_index_face(int entry)
{
    return records[entry].face;
}

extern "C" const char *busytex_font_index_psname(int entry)
{
    return records[entry].psname.c_str();
}

extern "C" void busytex_font_index_style(int entry, int *weight, int *width, int *slant,
                                         int *is_regular, int *is_bold, int *is_italic)
{
    const Record &record = records[entry];
    *weight = record.weight;
    *width = record.width;
    *slant = record.slant;
    *is_regular = record.is_regular;
    *is_bold = record.is_bold;
    *is_italic = record.is_italic;
}

extern "C" void busytex_font_index_opsize(int entry, double *design_size, double *min_size,
                                          double *max_size, int *subfamily_id, int *name_code)
{
    const Record &record = records[entry];
    *design_size = record.design_size;
    *min_size = record.min_size;
    *max_size = record.max_size;
    *subfamily_id = record.subfamily_id;
    *name_code = record.name_code;
}

extern "C" int busytex_font_index_name_count(int entry, int kind)
{
    return (int) records[entry].names[kind].size();
}

extern "C" const char *busytex_font_index_name(int entry, int kind, int position)
{
    return records[entry].names[kind][position].c_str();
}

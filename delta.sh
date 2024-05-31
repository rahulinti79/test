#!/bin/bash

# Ensure the file_paths.txt file exists
echo "============checking=========="
MODIFIED_FILE="file_paths.txt"
if [ ! -f "$MODIFIED_FILE" ]; then
    echo "$MODIFIED_FILE file not found!"
    exit 1
fi

# Start creating the package.xml
PACKAGE_XML="package.xml"
echo '<?xml version="1.0" encoding="UTF-8"?>' > "$PACKAGE_XML"
echo '<Package xmlns="http://soap.sforce.com/2006/04/metadata">' >> "$PACKAGE_XML"

# Declare associative arrays to store components by type
declare -A components
declare -A deleted_components

# Read the file paths and statuses and store components by type
while IFS= read -r line; do
    status=$(echo "$line" | awk '{print $1}')
    filepath=$(echo "$line" | awk '{print $2}')

    echo "Processing file: $filepath with status: $status" # Debug statement

    # Extract component type and name dynamically
    IFS='/' read -r -a path_parts <<< "$filepath"
    component_type=""
    component_name=""

    for part in "${path_parts[@]}"; do
        case "$part" in
            "classes") component_type="ApexClass";;
            "objects")
                if [[ "$filepath" == *"/fields/"* ]]; then
                    component_type="CustomField"
                    object_name=$(echo "$filepath" | grep -oP 'objects/\K[^/]+')
                    field_name=$(basename "${filepath%.field-meta.xml}")
                    component_name="${object_name}.${field_name}"
                else
                    component_type="CustomObject"
                    component_name=$(basename "${filepath%.*}")  # Remove extension
                fi
                ;;
            "flows") component_type="Flow";;
            "triggers") component_type="ApexTrigger";;
            "pages") component_type="ApexPage";;
            "components") component_type="ApexComponent";;
            "lwc") component_type="LightningComponentBundle";;
            "aura") component_type="AuraDefinitionBundle";;
        esac

        # Break if the component type has been determined
        if [ -n "$component_type" ]; then
            if [ -z "$component_name" ]; then
                component_name=$(basename "${filepath%.*}")  # Remove extension for other components
            fi
            break
        fi
    done

    if [ "$status" == "D" ]; then
        echo "Adding to deleted components: $component_type - $component_name" # Debug statement
        # Add to the deleted components array
        if [[ ! " ${deleted_components[$component_type]} " =~ " <members>${component_name}</members> " ]]; then
            deleted_components["$component_type"]+="\n        <members>${component_name}</members>"
        fi
    else
        echo "Adding to components: $component_type - $component_name" # Debug statement
        # Add to the components array
        if [ "$component_type" != "Unknown" ]; then
            if [[ ! " ${components[$component_type]} " =~ " <members>${component_name}</members> " ]]; then
                components["$component_type"]+="\n        <members>${component_name}</members>"
            fi
        fi
    fi
done < "$MODIFIED_FILE"

# Function to write components to package.xml and remove blank lines between <types> tags
write_types_section() {
    echo "    <types>" >> "$PACKAGE_XML"
    echo -e "$1" | awk 'NF' >> "$PACKAGE_XML"
    echo "        <name>$2</name>" >> "$PACKAGE_XML"
    echo "    </types>" >> "$PACKAGE_XML"
}

# Write components to package.xml
for type in "${!components[@]}"; do
    write_types_section "${components[$type]}" "$type"
done

# If there are deleted components, write to destructiveChanges.xml
if [ ${#deleted_components[@]} -gt 0 ]; then
    # Start creating the destructiveChanges.xml
    DESTRUCTIVE_XML="destructiveChanges.xml"
    echo '<?xml version="1.0" encoding="UTF-8"?>' > "$DESTRUCTIVE_XML"
    echo '<Package xmlns="http://soap.sforce.com/2006/04/metadata">' >> "$DESTRUCTIVE_XML"

    write_deleted_types_section() {
        echo "    <types>" >> "$DESTRUCTIVE_XML"
        echo -e "$1" | awk 'NF' >> "$DESTRUCTIVE_XML"
        echo "        <name>$2</name>" >> "$DESTRUCTIVE_XML"
        echo "    </types>" >> "$DESTRUCTIVE_XML"
    }

    # Write deleted components to destructiveChanges.xml
    for type in "${!deleted_components[@]}"; do
        write_deleted_types_section "${deleted_components[$type]}" "$type"
    done

    # Add version information and close the destructiveChanges.xml
    echo '    <version>52.0</version>' >> "$DESTRUCTIVE_XML"  # Change the version number if needed
    echo '</Package>' >> "$DESTRUCTIVE_XML"
    echo "destructiveChanges.xml created successfully."
else
    echo "No components marked for deletion. destructiveChanges.xml not created."
fi

# Add version information and close the package.xml
echo '    <version>52.0</version>' >> "$PACKAGE_XML"  # Change the version number if needed
echo '</Package>' >> "$PACKAGE_XML"
echo "package.xml created successfully."

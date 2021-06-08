/*
ImageJ/Fiji Script to do a segmentation of TIRF images
upon puncta formation of STIM or ORAI
You need to have 1 image open containing 1 channel and 1 z plane
The image can contain timepoints

Folder format:
Main folder:
	1_Images	// This folder is optional
	2_ROIs
	| 1_MCS
	3_Analysis

Video example on YouTube:
https://youtu.be/QEaP-abz-Ic
*/

// Define constants, set path and clear stuff before starting

ImageName = getTitle();
Extention = substring(ImageName, lastIndexOf(ImageName,"."));
SaveName = replace(ImageName, Extention, "");
run("Set Measurements...", "area mean redirect=None decimal=2");
run("Input/Output...", "jpeg=85 gif=-1 file=.csv use_file save_column save_row");
dir1 = getDirectory("Choose Main Directory");
dir1_2 = dir1 + "2_ROIs\\1_MCS\\";
dir1_3 = dir1 + "3_Analysis\\";
DeleteRoi();
MoreCells = "Yes";
CellId = 1;

while (MoreCells == "Yes") {
	selectWindow(ImageName);
	run("Duplicate...", "title=Temp duplicate");
	selectWindow(ImageName);
	
	// Select cell on which to perform the segmentation
	DeleteRoi();
	CreateCellRoi();
	
	// Find Maxima map from Image
	NoNextMaxima = "No";
	while (!(NoNextMaxima == "Yes")) {
	// Open a dialog to enter a noise value for the Maxima Map
		MaximaNoise = CustomMaximaMap();
		selectWindow(ImageName);
		MaximaMapName = "" + MaximaNoise + "_MaximaMap_Noise";
		run("Duplicate...", "title=" + MaximaMapName);
		run("Enhance Contrast", "saturated=0.1");
		run("Find Maxima...", "noise=" + MaximaNoise + " output=[Point Selection]");
	// Open a dialog to ask if we keep this segmentation or not
		NoNextMaxima = KeepMaximaMap(MaximaNoise);
		close(MaximaMapName);
	}
	selectWindow(ImageName);
	SliceNb = nSlices;
	for (i=1; i<SliceNb+1; i++) {
		selectWindow(ImageName);
		setSlice(i);
		run("Find Maxima...", "noise=" + MaximaNoise + " output=[Segmented Particles]");
	}
	run("Images to Stack", "name=Maxima_Map title=Segmented use");


	// Threshold of the image and create a mask
	selectWindow(ImageName);
	setLocation(40, 50);
	run("Threshold...");
	setAutoThreshold("Default dark");
	waitForUser("Threshold", "Set the threshold then press ok");
	run("Convert to Mask", "method=Default background=Dark black");
	rename("Mask");

	// Combine the mask and the maxima map
	imageCalculator("AND create stack", "Mask", "Maxima_Map");
	rename("Segmented_Image");
	close("Mask");
	close("Maxima_Map");

	// Create the ROIs for each Slice (Timepoint)
	selectWindow("Segmented_Image");
	for (i=1; i<SliceNb+1; i++) {
		setSlice(i);
		run("Analyze Particles...", "size=4-Infinity pixel add slice");
		if (roiManager("Count")<1) {
			continue
		}
		if (indexOf(SaveName, "_Cell")>0) {
			roiManager("save", dir1_2 + SaveName + "_Slice" + i + ".zip");
		} else if (indexOf(SaveName, "_Cell")==-1) {
			roiManager("save", dir1_2 + SaveName + "_Cell" + CellId + "_Slice" + i + ".zip");
		}
		roiManager("Deselect");
		roiManager("Delete");
	}
	MoreCells = AskIfMoreCells();
	CellId = CellId + 1;
	close("Segmented_Image");
	selectWindow("Temp");
	rename(ImageName);
}

// Extract the area and mean intensity for each Slice (Timepoint)
list1_2 = getFileList(dir1_2);
NbRois = newArray(list1_2.length);
SliceToGo = newArray(list1_2.length);
CellNb = newArray(list1_2.length);
StartingResult = newArray(list1_2.length);

for (i=0; i<list1_2.length; i++) {
	baseName = substring(list1_2[i], 0, indexOf(list1_2[i],"_Cell"));	
	if (indexOf(ImageName, baseName)==-1) {
		continue
	}
	SliceToGo[i] = substring(list1_2[i], indexOf(list1_2[i], "Slice")+5);
	SliceToGo[i] = replace(SliceToGo[i], ".zip", "");
	CellNb[i] = substring(list1_2[i], indexOf(list1_2[i], "Cell")+4, indexOf(list1_2[i], "_Slice"));
	roiManager("open", dir1_2 + list1_2[i]);
	setSlice(SliceToGo[i]);
	NbRois[i] = roiManager("Count");
	roiManager("multi-measure append");
	roiManager("Deselect");
	roiManager("Delete");
	if (i==0) {
		StartingResult[i] = NbRois[i];
	} else if (i>0) {
		StartingResult[i] = StartingResult[i-1] + NbRois[i];
	}
}
for (k=0; k<i; k++) {
	if (k==0) {
		for (j=0; j<NbRois[k]; j++) {
			setResult("SliceNb", j, SliceToGo[k]);
			setResult("CellNb", j, CellNb[k]);
		}
	} else if (k>0) {
		for (j=0; j<NbRois[k]; j++) {
			setResult("SliceNb", StartingResult[k-1] + j, SliceToGo[k]);
			setResult("CellNb", StartingResult[k-1] + j, CellNb[k]);
		}
	}
}	
updateResults();
PathTextFile = dir1_3 + replace(ImageName, Extention, ".txt");
String.copyResults;
TextFileOutput = File.open(PathTextFile);
print(TextFileOutput, String.paste);
File.close(TextFileOutput);

print("Job done");
selectWindow("Log");


// FUNCTIONS

function DeleteRoi() {
	RoiNb = roiManager("count");
	if (RoiNb > 0) {
		roiManager("Deselect");
		roiManager("Delete");
	}
}

function CreateCellRoi() {
	for (i=0; i<10; i++) {
		waitForUser("Roi around cell", "Create a ROI around the cell to analyze then press ok");
		RoiNb = roiManager("count");
		if (RoiNb == 0) {
			print("You need to create a ROI to define the cell of interest");
			selectWindow("Log");
		} else if (RoiNb > 1) {
			print("You need to keep only one ROI to define the cell of interest");
			selectWindow("Log");
		}
		if (RoiNb == 1) {
			roiManager("select", 0);
			run("Clear Outside", "stack");
			run("Select None");
			roiManager("Deselect");
			roiManager("Delete");
			break
		}
	}
}

function CustomMaximaMap() {
	Dialog.create("Custom - Maxima map");
	Dialog.addNumber("Custom Maxima",0);
	Dialog.show();
	MaximaNoise = Dialog.getNumber();
	return MaximaNoise;
}

function KeepMaximaMap(MaximaNoise) {
	setLocation(40, 50);
	waitForUser("Maxima", "Check the Maxima then press ok");
	Dialog.create("Maxima map");
	Dialog.addMessage("Maxima map with noise set to " + MaximaNoise);
	Dialog.addRadioButtonGroup("Keep this maxima map?",newArray("Yes", "No"),2,1,"No");
	Dialog.show();
	NoNextMaxima = Dialog.getRadioButton();
	return NoNextMaxima;
}

function AskIfMoreCells() {
	Dialog.create("More cells");
	Dialog.addRadioButtonGroup("More cells to analyze ?",newArray("Yes", "No"),2,1,"No");
	Dialog.show();
	MoreCells = Dialog.getRadioButton();
	return MoreCells;
}

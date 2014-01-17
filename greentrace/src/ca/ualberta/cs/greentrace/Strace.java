package ca.ualberta.cs.greentrace;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.FileNotFoundException;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.Iterator;

import au.com.bytecode.opencsv.CSVReader;
import au.com.bytecode.opencsv.CSVWriter;

public class Strace {
	//dirs of all the strace.txt files
	private static final String pathFile = "/path/to/strace/summary/file";
	private static final String SLOG = "/path/to/strace/log/file";
	
	//application version number file
	private static final String vFile = "/path/to/application/versions/file";
	
	/* this method gets a list of file paths
	 * @param path is the text file that stores the file paths
	 * @return dirs is an arraylist that holds these file paths
	 */
	public ArrayList<String> loadPath(String path) throws FileNotFoundException, IOException{
		String line;
		ArrayList<String> dirs = new ArrayList<String>();
		BufferedReader rd = new BufferedReader(new FileReader(path));
		while((line = rd.readLine()) != null){
			dirs.add(line);
		}
		return dirs;
	}
	
	// convert each system call invocation text summary to a csv file
	public void loadStrace(String dir) throws IOException{
		String line;
		String[] array;
		String[] path;
		
		path = dir.split("/");
		String csvFile = "/path/to/csv/file/to/hold/systemcallsummary/";
		
		BufferedReader rd = new BufferedReader(new FileReader(dir));
		
		CSVWriter cw = new CSVWriter(new FileWriter(csvFile));
		String [] title = "%time#seconds#usecs/call#calls#errors#syscall".split("#");
		cw.writeNext(title);
		
		BufferedWriter bw = new BufferedWriter(new FileWriter(SLOG,true));
		bw.write(path[5]);
		bw.newLine();
		
		//get rid of the first two lines
		line = rd.readLine();
		line = rd.readLine();
		
		while((line = rd.readLine()) != null){			
			array = line.trim().split(" +");
			if(array[0].equals("------")){
				   line = rd.readLine();
				   bw.write(line);
				   bw.newLine();
				   break;
				}
			System.out.println(array.length);
			if(array.length == 6){
				cw.writeNext(array);
			}else{
				String[] tmp = new String[6];
				tmp[5] = array[4];
				for(int i=0; i<4; i++){
					tmp[i] = array[i];
				}
				tmp[4] = "0";
				cw.writeNext(tmp);
			}

			System.out.println(line);
			for(int i =0; i < array.length; i++){
				System.out.println(array[i]);
			}
			System.out.println("\n");
		}
		cw.close();
		bw.close();
	}
	
	
	//get a list of unique system calls
	public ArrayList<String> getSystemCall(String vFile) throws FileNotFoundException, IOException{
		BufferedReader vApp = new BufferedReader(new FileReader(vFile));
		ArrayList<String> dirs = new ArrayList<String>();
		String line, tmp;
		//get all the dirs of stace csv file
		while((line = vApp.readLine()) != null){
			tmp = "path/to/a/systemcall/csv/file";
			dirs.add(tmp);
		}
		
		HashSet<String> sysCall = new HashSet<String>();
		//get all the unique system calls
		for(int i = 0; i < dirs.size(); i++ ){
			CSVReader cr = new CSVReader(new FileReader(dirs.get(i)));
			//first line is title
			cr.readNext();
			String [] csvLine;
			//int counter = 0;
			while((csvLine = cr.readNext()) != null){
				if (sysCall.add(csvLine[5])){
					System.out.println("Added the system call!\n");
				}
				else{
					//System.err.println("Duplicates!!!\n");
					continue;
				}

			}
			cr.close();
		}
		System.out.println("===========The size of the hashset is: " + sysCall.size() + "========" );
		
		ArrayList<String> systemCall = new ArrayList<String>();
		Iterator<String> sysCallIt = sysCall.iterator();
		while(sysCallIt.hasNext()){
			//System.out.println(sysCallIt.next());
			systemCall.add(sysCallIt.next());
		}
		vApp.close();
		systemCall.add(0, "POWER");
		return systemCall;
	}
	
	// merge mean power consumption and system call invocations
	public void sysCallMatrix(ArrayList<String> sysCall, String vFile) throws FileNotFoundException, IOException{
		String outputMatrix = "/path/to/output/file";
		BufferedReader vApp = new BufferedReader(new FileReader(vFile));
		ArrayList<String> dirs = new ArrayList<String>();
		String line, tmp;
		//get all the dirs of stace files
		while((line = vApp.readLine()) != null){
			tmp = "path/to/a/systemcall/csv/file";
			dirs.add(tmp);
		}
		vApp.close();
		
		BufferedReader power = new BufferedReader(new FileReader("/path/to/meanpower/file"));
		String [] meanPower = new String[dirs.size()];
		//get all the dirs of stace files
		for(int i = 0; i < meanPower.length; i++){
			meanPower[i] = power.readLine();
			System.err.println(meanPower[i]);
		}
		power.close();
		
		CSVWriter cw = new CSVWriter(new FileWriter(outputMatrix));
		cw.writeNext(sysCall.toArray(new String[sysCall.size()]));
		for(int i = 0; i < dirs.size(); i++ ){
			String [] syscall = new String[sysCall.size()];
			for (int index=0; index < syscall.length; index++){
				if( index == 0){
					syscall[index] = meanPower[i];
				}
				else{
				    syscall[index] = "0";
				}
			}
			
			CSVReader cr = new CSVReader(new FileReader(dirs.get(i)));
			//first line is title
			cr.readNext();
			String [] csvLine;
			//int counter = 0;
			while((csvLine = cr.readNext()) != null){
				if (sysCall.contains(csvLine[5])){
					syscall[sysCall.indexOf(csvLine[5])] = csvLine[3];
					System.out.println(csvLine[5] + " : "+ csvLine[3] + "\n");
				}
				else{
					continue;
				}

			}
			cw.writeNext(syscall);
			cr.close();
		}
		cw.close();
		System.err.println("Done!!!");
	}
	
	public static void main(String[] args){
		Strace s = new Strace();
				
		//pre-processe data
		ArrayList<String> fileDir = new ArrayList<String>();
		try {
			fileDir = s.loadPath(pathFile);
		} catch (IOException e) {
			// TODO Auto-generated catch block
			e.printStackTrace();
		}
		for(int i = 0; i < fileDir.size(); i++ ){
			try{
				s.loadStrace(fileDir.get(i));
			} catch (IOException e) {
				// TODO Auto-generated catch block
				e.printStackTrace();
			}
		}
		
		//generate system call matrix
		ArrayList<String> sysCall = new ArrayList<String>();
		try {
			sysCall = s.getSystemCall(vFile);
			s.sysCallMatrix(sysCall, vFile);
		} catch (FileNotFoundException e) {
			// TODO Auto-generated catch block
			e.printStackTrace();
		} catch (IOException e) {
			// TODO Auto-generated catch block
			e.printStackTrace();
		}
	}
}
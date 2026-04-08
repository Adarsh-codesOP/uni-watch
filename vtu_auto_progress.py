import requests
import json
import time
import os
import sys
import logging

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

# Setup Logging
log_formatter = logging.Formatter('%(asctime)s | %(levelname)s | %(message)s')
logger = logging.getLogger('vtu_automater')
logger.setLevel(logging.DEBUG)

file_handler = logging.FileHandler('api_responses.log', 'w', encoding='utf-8')
file_handler.setFormatter(log_formatter)
logger.addHandler(file_handler)

# VTU Portal Base URL
BASE_URL = "https://online.vtu.ac.in/api/v1"

# Load Credentials
EMAIL = os.environ.get("VTU_EMAIL")
PASSWORD = os.environ.get("VTU_PASSWORD")

if not EMAIL or not PASSWORD:
    print("[-] Error: Make sure VTU_EMAIL and VTU_PASSWORD are set in the .env file.")
    sys.exit(1)

session = requests.Session()
session.headers.update({
    "Accept": "application/json",
    "Content-Type": "application/json",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36",
    "Origin": "https://online.vtu.ac.in",
    "Referer": "https://online.vtu.ac.in/"
})

def login():
    print(f"[*] Attempting to login as {EMAIL}...")
    logger.info(f"Login attempt with {EMAIL}")
    login_url = f"{BASE_URL}/auth/login"
    payload = {"email": EMAIL, "password": PASSWORD}
    
    try:
        response = session.post(login_url, json=payload)
        data = response.json()
        logger.info(f"Login Response: HTTP {response.status_code} | Body: {json.dumps(data)}")
        
        if response.status_code == 200 and data.get("success"):
            print("[+] Login Successful!")
            return True
        else:
            print("[-] Login Failed. Check log for details.")
            return False
    except Exception as e:
        logger.error(f"Login Error: {e}", exc_info=True)
        return False

def get_enrolled_courses():
    print("\n[*] Fetching enrolled courses...")
    logger.info("Fetching enrolled courses...")
    enrollments_url = f"{BASE_URL}/student/my-enrollments"
    
    try:
        response = session.get(enrollments_url)
        data = response.json()
        logger.info(f"Enrollments Response: HTTP {response.status_code} | Body: {json.dumps(data)}")
        
        if response.status_code == 200 and data.get("success"):
            courses = data.get("data", [])
            print(f"[+] Found {len(courses)} enrolled course(s).")
            return courses
        return []
    except Exception as e:
        logger.error(f"Enrollments Error: {e}", exc_info=True)
        return []

def get_course_details(course_slug):
    course_url = f"{BASE_URL}/student/my-courses/{course_slug}"
    try:
        response = session.get(course_url)
        data = response.json()
        logger.info(f"Course Details ({course_slug}) Response: HTTP {response.status_code} | Body length: {len(str(data))}")
        if response.status_code == 200 and data.get("success"):
            return data.get("data", {})
    except Exception as e:
        logger.error(f"Course Details Error for {course_slug}: {e}", exc_info=True)
    return None

def mark_video_complete(course_slug, lecture_id, lecture_title):
    progress_url = f"{BASE_URL}/student/my-courses/{course_slug}/lectures/{lecture_id}/progress"
    
    # We will loop sending duration updates up to 100 times to force completion.
    max_attempts = 150
    current_time = 0
    percent = 0
    
    for attempt in range(1, max_attempts + 1):
        # We step through the video in chunks. Giving the backend realistic increments.
        current_time += 120 
        payload = {
            "current_time_seconds": current_time,
            "total_duration_seconds": 3600, # Assumed 1hr default if unknown
            "seconds_just_watched": 120 
        }
        
        try:
            response = session.post(progress_url, json=payload)
            res_data = response.json()
            data_dict = res_data.get("data", {})
            
            is_completed = data_dict.get("is_completed", False)
            percent = data_dict.get("percent", 0)
            
            logger.info(f"Progress Ping ({lecture_title}) Att {attempt}: HTTP {response.status_code} | Body: {json.dumps(res_data)}")
            
            # First attempt print to let user know where we are starting from
            if attempt == 1:
                print(f"    [*] {lecture_title} - Started at: {percent}%")
            
            if is_completed or percent >= 98:
                print(f"    [+] Successfully hit {percent}% completion: {lecture_title}")
                return # Done, we can move to the next video
            
            # Print a progress update every 10 attempts to prove it's not frozen
            if attempt % 10 == 0:
                print(f"        -> Still pumping... currently at {percent}%")
            
            if attempt == max_attempts:
                print(f"    [?] Reached hard limit of {max_attempts} attempts: {lecture_title} - Last Percent: {percent}%")
                
            time.sleep(0.5)
        except Exception as e:
            logger.error(f"Progress Ping Error ({lecture_title}): {e}", exc_info=True)
            print(f"    [-] Network error, skipping {lecture_title}")
            break

def bypass_all_courses():
    if not login():
        return
        
    enrollments = get_enrolled_courses()
    
    for enrollment in enrollments:
        details = enrollment.get("details", {})
        course_slug = details.get("slug")
        course_title = details.get("title")
        
        if not course_slug:
            continue
            
        print(f"\n==============================================")
        print(f"[*] Processing Course: {course_title}")
        print(f"==============================================")
        
        course_data = get_course_details(course_slug)
        if not course_data:
            continue
            
        lessons = course_data.get("lessons", [])
        total_lectures = 0
        
        for week in lessons:
            week_name = week.get("name", "Unknown Week")
            print(f"\n  [*] Opening {week_name}...")
            
            lectures = week.get("lectures", [])
            for lecture in lectures:
                lecture_id = lecture.get("id")
                lecture_title = lecture.get("title", f"Lecture {lecture_id}")
                
                mark_video_complete(course_slug, lecture_id, lecture_title)
                total_lectures += 1
                
        print(f"\n[+] Finished pumping {total_lectures} lectures for {course_title}.")

if __name__ == "__main__":
    print("Starting VTU Auto-Progress Bypass...")
    bypass_all_courses()
    print("\n[+] All tasks finished. Check 'api_responses.log' to verify API details!")

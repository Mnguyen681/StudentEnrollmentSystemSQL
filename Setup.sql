SET echo ON
SET serveroutput ON

spool E:\is480\setup.txt

-- Martin Nguyen 015190875 
-- Final Project Setup.sql 

CREATE OR REPLACE PACKAGE ENROLL IS 

--1) CREATE valid_student procedure
  PROCEDURE proc_validate_student(
  p_snum in students.snum%type,
  p_error_text out varchar2);

--1) CREATE valid_callnum function
  FUNCTION func_validate_callnum(
  p_callnum schclasses.callnum%type)
  RETURN varchar2;

--2) REPEAT ENROLLMENT
  PROCEDURE proc_repeat_enrollment(
  p_snum in students.snum%type,
  p_callnum in enrollments.callnum%type,
  p_error_text out varchar2);

--3) DOUBLE ENROLLMENT
  PROCEDURE proc_double_enrollment(
  p_snum in students.snum%type,
  p_callnum in enrollments.callnum%type,
  p_error_text out varchar2);

--4) 15-hour RULE
  PROCEDURE proc_validate_total_credit_hour(
  p_snum enrollments.snum%type,
  p_callnum schclasses.callnum%type,
  p_error_text out varchar2);

--5) STANDING REQUIREMENT
  PROCEDURE proc_standing_requirement(
  p_snum enrollments.snum%type,
  p_callnum enrollments.callnum%type,
  p_error_text out varchar2);

-- 6) Disqualified Student 
  PROCEDURE proc_disqualified_student(
  p_snum enrollments.snum%type
  p_error_text OUT varchar2);

-- 7) CAPACITY  
  FUNCTION func_valid_class_capacity(
  p_callnum schclasses.callnum%type) 
  RETURN varchar2;

-- 8) WAITLIST
  PROCEDURE proc_waitlist(
  p_snum students.snum%type,
  p_callnum enrollments.callnum%type,
  p_error_msg OUT varchar2);

-- 9)Repeat Waitlist
  PROCEDURE proc_repeatwaitlist(
  p_snum students.snum%type,
  p_callnum enrollments.callnum%type,
  p_error_msg OUT varchar2);

-- 10) 
  PROCEDURE addme(
  p_snum students.snum%type,
  p_callnum enrollments.callnum%type,
  p_error_msg OUT varchar2);

END enroll;
/
show error;

CREATE OR REPLACE PACKAGE BODY ENROLL IS 

-- 1) VALID STUDENT
  PROCEDURE proc_validate_student(
    p_snum IN students.snum%type,
    p_error_text OUT varchar2) AS
    v_count number(3);
  
  BEGIN
    SELECT count(*) INTO v_count
    FROM students
    WHERE snum=p_snum;
    
    IF v_count = 0 THEN
      p_error_text:='Sorry, the student with number ' || p_snum || ' is not in our database. ';
    END IF;
  END;

-- 1) VALID CALLNUM 
  Function func_validate_callnum(
    p_callnum schclasses.callnum%type)
  RETURN varchar2 AS
    v_callnum number(3);
  
  BEGIN 
    SELECT count(*) INTO v_callnum
    FROM schclasses
    WHERE callnum=p_callnum;
    
    IF v_callnum = 0 then
      RETURN 'Class number ' || p_callnum || ' is invalid. ';
    ELSE
      RETURN null;
    END IF;
  END;

-- 2) REPEAT ENROLLMENT
  PROCEDURE proc_repeat_enrollment(
      p_snum IN students.snum%type,
      p_callnum IN enrollments.callnum%type,
      p_error_text OUT varchar2) AS
      v_count number(3);
    BEGIN
      SELECT count(*) INTO v_count
      FROM enrollments
      WHERE snum = p_snum AND 
      callnum = p_callnum;
      
      IF v_count != 0 THEN
        p_error_text:='Sorry, the student with number ' || p_snum || ' already enrolled in class number ' || p_callnum || '. ';
      END IF;
    END;

-- 3) DOUBLE ENROLLMENT 
  PROCEDURE proc_double_enrollment(
    p_snum IN students.snum%type,
    p_callnum IN enrollments.callnum%type,
    p_error_text OUT varchar2) AS
    v_dept schclasses.dept%type;
    v_cnum schclasses.dept%type;
    v_count number(3);
    v_section number(2);
  
  BEGIN
    --to find the dept and cnum of the class the student wants to take
    SELECT dept, cnum INTO v_dept, v_cnum
    FROM schclasses
    WHERE callnum=p_callnum;
    --use exception no_data_found so that if the classnum is not in the enrollments table yet, the program will not crash
    
    BEGIN
      --find the section of the class already took
      SELECT section INTO v_section
      FROM schclasses, enrollments
      WHERE schclasses.CALLNUM=enrollments.CALLNUM AND 
        p_snum = enrollments.snum AND
        v_dept = schclasses.dept AND
        v_cnum = schclasses.cnum;
    
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        null;
      WHEN TOO_MANY_ROWS THEN
        null;
    END;
    --check if the student already took the same class but different sections
    
    SELECT count(*) INTO v_count
    FROM enrollments, schclasses
    WHERE enrollments.callnum = schclasses.callnum AND
      dept=v_dept AND
      cnum=v_cnum AND
      snum=p_snum;
    
    IF v_count != 0 THEN
      p_error_text:='You are already enrolled in this class ' || v_dept || v_cnum || ' in section ' || v_section || '. ';
      --dbms_output.put_line(p_error_text);
    END IF;
  END;

-- 4) 15 - Hour rule 
  PROCEDURE proc_validate_total_credit_hour(
    p_snum enrollments.snum%type,
    p_callnum schclasses.callnum%type,
    p_error_text OUT varchar2) AS
    v_enrollment_crhr number(3);
    v_add_crhr number(3);
  
  BEGIN
    --get credit hr of course want to add
    SELECT crhr INTO v_add_crhr
    FROM schclasses sch, courses c
    WHERE sch.callnum=p_callnum
    AND sch.dept=c.dept
    AND sch.cnum=c.cnum;
    --get credit of already enrollment
    SELECT nvl(sum(crhr),0) INTO v_enrollment_crhr
    FROM enrollments e, schclasses sch, courses c
    WHERE e.snum = p_snum AND
      e.callnum = sch.callnum AND
      sch.dept=c.dept AND
      sch.cnum=c.cnum AND
      grade is null;
    
    IF v_add_crhr + v_enrollment_crhr <=15 THEN
      p_error_text:= null;
    ELSE
      p_error_text:='Sorry, the student with the number ' || p_snum || ' have reached the total limit units. ';
    END IF;
  END;

-- 5) STANDING REQUIREMENT 
  PROCEDURE proc_standing_requirement(
    p_snum enrollments.snum%type,
    p_callnum enrollments.callnum%type,
    p_error_text OUT varchar2) AS
    v_stu_standing number(1);
    v_callnum_standing number(1);
    v_dept schclasses.dept%type;
    v_cnum schclasses.dept%type;
  
  BEGIN
    -- get standing of the student
    SELECT standing INTO v_stu_standing
    FROM students
    WHERE snum=p_snum;

    -- get standing of the class
    SELECT standing, courses.dept, courses.cnum INTO v_callnum_standing, v_dept, v_cnum
    FROM courses, schclasses
    WHERE schclasses.callnum=p_callnum
    AND courses.dept=schclasses.dept
    AND courses.cnum=schclasses.cnum;

    -- compare between standing of student and standing of the class
    IF v_stu_standing < v_callnum_standing THEN
      p_error_text:='Sorry, your standing is ' || v_stu_standing || '. It is lower than the standing of the class ' || v_dept || v_cnum || ' which has standing of ' || v_callnum_standing || '. ';
    END IF;
  END;

-- 6) Disqualified Student 
  PROCEDURE proc_disqualified_student(
    p_snum enrollments.snum%type
    p_error_text OUT varchar2) AS
    v_stu_standing number(1);
    v_stu_gpa number(2,1);
  
  BEGIN
-- get standing of the student
    SELECT standing INTO v_stu_standing
    FROM students
    WHERE snum=p_snum;

-- get student gpa 
    SELECT gpa INTO v_stu_gpa
    FROM students 
    WHERE snum=p_snum;

-- compare between standing of student and standing of the class
    IF (v_stu_standing = 1 OR v_stu_gpa < 2.0) THEN
      p_error_text:='Sorry, the student is disqualified. Your standing is ' || v_stu_standing || '. Your gpa is  ' || v_stu_gpa || ' Non-Freshmen students must have a gpa of at least 2.0. ';
    END IF;
  END;

-- 7) Capacity  
  FUNCTION func_valid_class_capacity(
    p_callnum schclasses.callnum%type 
    RETURN varchar2) AS
    v_capacity number(3);
    v_snum number(3);

  BEGIN
--find maximum capacity of the class
    SELECT capacity INTO v_capacity
    FROM schclasses
    WHERE p_callnum = schclasses.callnum;
    
--find current space of the class
    SELECT count(*) INTO v_snum
    FROM enrollments
    WHERE enrollments.callnum=p_callnum AND
      grade is null;
    
    IF v_snum < v_capacity THEN
      RETURN null;
    ELSE
      RETURN 'Sorry this class ' || p_callnum || ' is already full. Please choose another class. ';
    END IF;
  END;

-- 8) Waitlist 

  PROCEDURE proc_waitlist(
    p_snum students.snum%type,
    p_callnum enrollments.callnum%type,
    p_error_msg OUT varchar2) AS
    v_error_text varchar(10000);
    v_count number(3);

  BEGIN
    SELECT count(*) INTO v_count
    FROM waitlist
    WHERE p_snum=snum AND
      p_callnum=callnum;
    
    IF v_count != 0 THEN
      p_error_msg:='The student with the student number ' || p_snum || ' is already on waiting list for the class ' || p_callnum || '. ';
    END IF;
  END;  


-- 9)Repeat Waitlist
  PROCEDURE proc_repeatwaitlist(
    p_snum students.snum%type,
    p_callnum enrollments.callnum%type,
    p_error_msg OUT varchar2) AS
    v_error_text varchar(10000);
    v_count number(3);
  
  BEGIN
    SELECT count(*) INTO v_count
    FROM waitlist
    WHERE p_snum=snum AND
      p_callnum=callnum;
    
    proc_waitlist(p_snum, p_callnum, v_error_text);
    p_error_msg:=v_error_text;

    IF p_error_msg is null THEN
      v_count := v_count + 1;
      INSERT INTO waitlist VALUES(p_callnum, waitnum.nextval, p_snum, sysdate);        
      commit;
      p_error_msg:=('Sorry the class ' || p_callnum || ' is already full. ' || 'Student with the ID number ' || p_snum || ' is on waitlist #' || v_count || ' for class ' || p_callnum || '. ');
    ELSE
      p_error_msg:=(p_snum || ' is already on waitlist number #' || v_count || ' for class number ' || p_callnum || '. ');
    END IF;
  END;  

  -- 10) 
  PROCEDURE addme(
    p_snum students.snum%type,
    p_callnum enrollments.callnum%type,
    p_error_msg OUT varchar2) AS
    v_error_text varchar2(10000);
    v_dept varchar2(3);
    v_cnum varchar2(30);
    v_section number(2);
    v_count number(3);
  
  BEGIN
    -- 1- check student validation
    proc_validate_student(p_snum, v_error_text);
    p_error_msg:=v_error_text;
    -- 1- check valid class number
    v_error_text:=func_validate_callnum(p_callnum);
    p_error_msg:=p_error_msg || v_error_text;
    IF p_error_msg is null THEN
      --get the class description and section number of p_callnum
      SELECT courses.dept, courses.cnum, schclasses.section INTO v_dept, v_cnum, v_section
      FROM courses, schclasses
      WHERE p_callnum = callnum AND
      schclasses.dept = courses.dept AND
      schclasses.cnum = courses.cnum;
      -- 2 - check if the student already enrolled in the class
      proc_repeat_enrollment(p_snum, p_callnum, v_error_text);
      p_error_msg:=p_error_msg || v_error_text;
      --check if the student enrolled in the class, but different section
      IF p_error_msg is null THEN      
        proc_double_enrollment(p_snum, p_callnum, v_error_text);
        p_error_msg:=p_error_msg || v_error_text;
      END IF;
      -- 5 - check standing of student, compare to the standing requirement of the class
      proc_standing_requirement(p_snum, p_callnum, v_error_text);
      p_error_msg:=p_error_msg || v_error_text;
      -- 4 - check if student have more than 15 units
      proc_validate_total_credit_hour(p_snum, p_callnum, v_error_text);
      p_error_msg:=p_error_msg || v_error_text;
      IF p_error_msg is null THEN
        -- 7 - check if class is full or not after the student enrolls
        v_error_text:=func_valid_class_capacity(p_callnum);
        p_error_msg:=p_error_msg || v_error_text;
        IF p_error_msg is null THEN
          INSERT INTO enrollments VALUES(p_snum, p_callnum, null);
          dbms_output.put_line('Congratulations !!! ' || 'The student number ' || p_snum || ' has successfully enrolled in class ' || p_callnum || ' which is ' || v_dept || ' ' || v_cnum || ' section ' || v_section || '. ');
          commit;
        ELSE
          -- 8 -check if student is already on the waiting list
          SELECT count(*) INTO v_count
          FROM waitlist
          WHERE callnum=p_callnum;
          proc_waitlist(p_snum, p_callnum, v_error_text);
          p_error_msg:=v_error_text;
          IF p_error_msg is null THEN
            v_count := v_count + 1;
            INSERT INTO waitlist VALUES(p_callnum, waitnum.nextval, p_snum, sysdate);        
            commit;
            dbms_output.put_line('Sorry the class ' || p_callnum || ' is already full. ' || 'Student with the ID number ' || p_snum || ' is on waitlist #' || v_count || ' for class ' || p_callnum || '. ');
          ELSE
            dbms_output.put_line(p_snum || ' is already on waitlist number #' || v_count || ' for class number ' || p_callnum || '. ');
          END IF;
        END IF;
      ELSE
        dbms_output.put_line(p_error_msg);
      END IF;
    ELSE
      dbms_output.put_line(p_error_msg);
    END IF;
  END;  


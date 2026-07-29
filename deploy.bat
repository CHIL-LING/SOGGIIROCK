@echo off
cd /d C:\FlutterProjects\flutter_application_1steno_app

echo 빌드 중...
flutter build web --release --base-href "/SOGGIIROCK/" --no-tree-shake-icons
if errorlevel 1 (
    echo 빌드 실패!
    pause
    exit /b 1
)

echo docs 폴더에 복사 중...
xcopy /E /I /Y build\web docs

echo GitHub에 올리는 중...
git add .
git commit -m "업데이트"
git push

echo 완료!
pause
import io
import json
import math
import struct
import wave
from pathlib import Path
from .session import init_db, SessionLocal
from . import crud
from ..services import heritage_service
from ..storage import manager

ROOT_DIR = Path(__file__).resolve().parents[3]
DATASETS_DIR = ROOT_DIR / "datasets"

DEFAULT_CATALOG = {
    "bai_001.mp3": {
        "title": "Hò Mái Nhì (chuyển Nam Bình - Sông Hương tự tình)",
        "type": "Ca Huế",
        "genre": "Ca Huế trữ tình, hơi Ai - Oán",
        "artist": "Nghệ nhân dân gian Huế",
        "instruments": "đàn tranh, đàn nguyệt, đàn nhị, đàn bầu, song loan",
        "bpm": 52.0,
        "lyrics": "[Intro]\nSông Hương nọ khác chi tấm can tràng lai láng,\nKhi thì mờ mịt như màn sương buổi sáng,\nKhi thì tỏ rạng dưới những áng mây chiều,\nKhi thì lờ đờ dưới vầng nguyệt trong veo.\n\n[Verse 1]\nAnh ơi, đây bạc thiếp, đó vàng gieo,\nKhiến chi anh nhớ tưởng đến mái chèo năm xưa.\n\n[Verse 2]\nYêu nhau đành chịu, xa nhau bởi vì đâu?\nLệ tình chan chứa vò võ canh thâu,\nChảy lòng như lửa thêm dầu,\nNghĩa tương giao trăm năm coi như buổi ban đầu.",
    },
    "bai_002.mp3": {
        "title": "Hò giã gạo xứ Huế (Hò Khoan - hát đối đáp)",
        "type": "Ca Huế",
        "genre": "Hò lao động đối đáp Bình Trị Thiên",
        "artist": "Nghệ nhân dân gian Huế",
        "instruments": "chày cối gỗ, sanh tiền, mõ tre, đàn tranh, đàn nguyệt, đàn nhị, trống bản",
        "bpm": 100.0,
        "lyrics": "[Verse 1]\nBước tới nơi đây cầm chày giã gạo,\nTôi xin chào lê, chào lựu, chào kẻ cựu người tân.\nTrước tiên, tôi xin chào anh chị nông dân,\nKẻ xa xôi tôi chào trước, kẻ gần sau tôi sẽ chào.\nMở lời em chào nam, chào bắc,\nChào người ngang vai, chào người quân tử,\nChào gái thuyền quyên trong họ ngoài làng.",
    },
    "bai_003.mp3": {
        "title": "Lý Mười Thương",
        "type": "Ca Huế",
        "genre": "Dân ca lý Huế, điệu Lý tươi vui",
        "artist": "Nghệ nhân dân gian Huế",
        "instruments": "sáo trúc, đàn tranh, đàn bầu, đàn nhị, đàn nguyệt, trống cơm, song loan",
        "bpm": 95.0,
        "lyrics": "[Verse 1]\nMột thương tóc xõa ngang vai,\nHai thương đi đứng vẻ người có duyên.\n\n[Verse 2]\nBa thương ăn nói dịu hiền,\nBốn thương mơ mộng mắt huyền thêm xinh.\n\n[Verse 3]\nNăm thương dáng điệu thanh thanh,\nSáu thương nón Huế những vành nên thơ.\n\n[Verse 4]\nBảy thương những phút mong chờ,\nTám thương bến đợi Hương Giang hữu tình.\n\n[Verse 5]\nChín thương em bước nhẹ nhàng,\nMười thương tà áo dịu dàng bay xa.",
    },
    "bai_004.mp3": {
        "title": "Lý Ngựa Ô",
        "type": "Ca Huế",
        "genre": "Dân ca lý Huế, sôi động",
        "artist": "Nghệ nhân dân gian Huế",
        "instruments": "trống cái, đàn nhị, mõ tre, đàn tranh, trống con",
        "bpm": 115.0,
        "lyrics": "[Verse 1]\nNgựa ô ơi ngựa ô,\nCám cảnh dưới hồ bắt lên mà thắng.\nTính tang lông căng xinh, tính tang lông căng xinh.\nThiếp đưa chàng chinh lại về dinh,\nThiếp đưa chàng chinh lại về dinh.\n\n[Verse 2]\nNgựa ô ơi ngựa ô,\nEm sắm kiệu vàng em ra cửa Bắc,\nHồ lục làng trong ghép bộ để rước tình thăng.\nTính tang lông căng xinh, tính tang lông căng xinh.\nThiếp đưa chàng chinh lại về dinh,\nThiếp đưa chàng chinh lại về dinh.",
    },
    "bai_005.mp3": {
        "title": "Nón bài thơ xứ Huế (tổ khúc dân ca)",
        "type": "Ca Huế",
        "genre": "Dân ca Huế - tổ khúc, điệu Bắc pha Nam",
        "artist": "Nghệ nhân dân gian Huế",
        "instruments": "đàn tranh, đàn nhị, sáo trúc, sinh tiền, trống cơm, đàn bầu",
        "bpm": 90.0,
        "lyrics": "[Verse 1]\nNón nhà bài thơ, nón xinh em tặng cho chàng,\nĐể làm kỷ niệm những ngày qua đò.\n\n[Verse 2]\nQuê em từ thuở bao giờ,\nGái Nam giao dệt lụa tơ, nón nhà bài thơ.\nNón nghiêng nghiêng chẳng nón ai,\nLá ơi lá úp thêm mềm.\n\n[Chorus]\nHồ tang hồ tang tình tang, gái Huế nhà hồ tang tình tang.\nGái Huế nhà hồ tang tình tang, tình tang hồ tang tình tang.",
    },
    "bai_006.mp3": {
        "title": "Tứ Đại Cảnh - Đêm Thất Tịch",
        "type": "Ca Huế",
        "genre": "Ca Huế Tứ Đại Cảnh, hơi Dựng pha Oán",
        "artist": "Ưng Bình Thúc Giạ Thị",
        "instruments": "đàn tranh, đàn nhị, đàn nguyệt, song loan, phách",
        "bpm": 50.0,
        "lyrics": "[Verse 1]\nSông Ngân Hà bao nhiêu nước,\nChim Ô Thước bắc cầu.\nSông dẫu cạn hãy sâu,\nAi xui lòng chẳng nài công phu trông mấy vạn niên thu.\n\n[Verse 2]\nĐêm Thất Tịch duyên định từ lâu,\nGhi lời hẹn với nhau,\nQua nhịp cầu Chức Nữ với Khiên Ngưu cho tỏ dạ vài câu.\n\n[Verse 3]\nCâu ly biệt ai biệt lòng ai,\nAi nhìn mặt không sai.\nMột năm ròng có một bữa mà thôi cho gặp gỡ lại vui.",
    },
    "bai_007.mp3": {
        "title": "Tự tình Hò giã gạo (trích đoạn biểu diễn)",
        "type": "Ca Huế",
        "genre": "Hò đối đáp Huế, điệu Bắc pha Nam",
        "artist": "Nghệ nhân dân gian Huế",
        "instruments": "chày gỗ, song lang, đàn tranh, đàn nguyệt, đàn nhị, sáo trúc, trống chiến",
        "bpm": 118.0,
        "lyrics": "[Verse 1]\nGiữa chừ viên cỏ điêu la,\nLà có dân quê giã gạo.\nHay đâu có thiếp có chàng,\nUyên ương quân tử đối đàm gặp nhau.\n\n[Verse 2]\nChừ phen đây không có dây tơ Ba Nguyệt,\nXe duyên xe nợ không biết tính làm sao.\nThuyền quyên mới gặp anh hào,\nMột đôi câu nhân nghĩa ta hạp nhau trao gửi.",
    },
    "inst_001.mp3": {
        "title": "Kim Tiền (Độc tấu Đàn Nguyệt Nhã Nhạc)",
        "type": "Nhạc cụ truyền thống Huế",
        "genre": "Độc tấu Đàn Nguyệt, Hơi Bắc Nhã nhạc",
        "artist": "Nghệ nhân dân gian Huế",
        "instruments": "đàn nguyệt (đàn kìm)",
        "bpm": 85.0,
        "lyrics": "[Instrumental]",
    },
    "inst_002.mp3": {
        "title": "Long Hổ (Độc tấu Đàn Nguyệt Nhã Nhạc)",
        "type": "Nhạc cụ truyền thống Huế",
        "genre": "Độc tấu Đàn Nguyệt, Hơi Bắc Nhã nhạc",
        "artist": "Nghệ nhân dân gian Huế",
        "instruments": "đàn nguyệt (đàn kìm)",
        "bpm": 90.0,
        "lyrics": "[Instrumental]",
    },
    "inst_003.mp3": {
        "title": "Lưu Thủy (Độc tấu Đàn Nguyệt Nhã Nhạc)",
        "type": "Nhạc cụ truyền thống Huế",
        "genre": "Độc tấu Đàn Nguyệt, Hơi Bắc Nhã nhạc",
        "artist": "Nghệ nhân dân gian Huế",
        "instruments": "đàn nguyệt (đàn kìm)",
        "bpm": 78.0,
        "lyrics": "[Instrumental]",
    },
    "inst_004.mp3": {
        "title": "Xuân Phong (Độc tấu Đàn Nguyệt Nhã Nhạc)",
        "type": "Nhạc cụ truyền thống Huế",
        "genre": "Độc tấu Đàn Nguyệt, Hơi Bắc Nhã nhạc",
        "artist": "Nghệ nhân dân gian Huế",
        "instruments": "đàn nguyệt (đàn kìm)",
        "bpm": 82.0,
        "lyrics": "[Instrumental]",
    },
    "inst_005.mp3": {
        "title": "Đăng Đàn Cung (Độc tấu Đàn Nguyệt Nhã Nhạc)",
        "type": "Nhạc cụ truyền thống Huế",
        "genre": "Độc tấu Đàn Nguyệt, Quốc thiều triều Nguyễn",
        "artist": "Nghệ nhân dân gian Huế",
        "instruments": "đàn nguyệt (đàn kìm)",
        "bpm": 65.0,
        "lyrics": "[Instrumental]",
    },
    "inst_006.mp3": {
        "title": "Đại nhạc song tấu trống kèn (Nhã nhạc cung đình)",
        "type": "Nhã nhạc cung đình Huế",
        "genre": "Đại nhạc lễ cung đình, song tấu trống kèn",
        "artist": "Nghệ nhân dân gian Huế",
        "instruments": "kèn bầu, kèn bóp, trống chiến, trống nhạc lễ",
        "bpm": 105.0,
        "lyrics": "[Instrumental]",
    },
}

MUSICOLOGY_EXTENSIONS = {
    "bai_001.mp3": {
        "mode_system": "Hơi Nam - Nam Ai / Nam Bình (Ai oán, nỉ non, trữ tình)",
        "verse_structure": "Lục bát biến thể / Hò sông nước Bình Trị Thiên",
        "rhyme_guide": "Vần bằng trắc xen kẽ, nhịp buông thả tự do (rubato), ngắt nhịp cuối câu buông dài với tiếng 'ơ... hò...'",
        "lyrics_with_ornaments": "[Intro]\nSông Hương nọ khác chi (ơ) tấm can tràng lai láng (a í a),\nKhi thì mờ mịt (ơ) như màn sương buổi sáng,\nKhi thì tỏ rạng dưới những áng mây chiều,\nKhi thì lờ đờ dưới vầng nguyệt trong veo (ơ hò).\n\n[Verse 1]\nAnh ơi, đây bạc thiếp (ơ) đó vàng gieo,\nKhiến chi anh nhớ tưởng (tình tang) đến mái chèo năm xưa.\n\n[Verse 2]\nYêu nhau đành chịu, xa nhau bởi vì đâu (a í a)?\nLệ tình chan chứa vò võ canh thâu,\nChảy lòng như lửa thêm dầu,\nNghĩa tương giao trăm năm coi như buổi ban đầu.\n\n[Chorus]\nTrên đường, trên đường ân ái (ơ),\nThấy chông gai ta càng hăng hái (tình tang)!\nMuôn sự xem thường, nếm chua cay nhưng mà hơn mật hơn đường.\nAi cho tiền của không ân,\nBằng xây đắp tấm yêu cho tròn.\n\n[Outro]\nĐã nắm lấy mối sầu,\nĐau khổ là quy luật của tình chung.\nDằng dặc long đong,\nNguyện cũng không giảm sai tấc lòng (ơ hò).",
        "is_instrumental": False,
        "featured_in_creation": True,
    },
    "bai_002.mp3": {
        "mode_system": "Hơi Bắc kết hợp Hơi Nam (Rộn ràng, đối đáp lao động)",
        "verse_structure": "Song thất lục bát & câu đối dân gian",
        "rhyme_guide": "Vần liền vần cách, nhịp chày 2/4 dồn dập, tiếng hô xô 'khoan hỡi khoan hò' đệm nhịp sau mỗi vế",
        "lyrics_with_ornaments": "[Verse 1]\nBước tới nơi đây cầm chày giã gạo (khoan hỡi khoan hò),\nTôi xin chào lê, chào lựu, chào kẻ cựu người tân.\nTrước tiên, tôi xin chào anh chị nông dân (ơ hò),\nKẻ xa xôi tôi chào trước, kẻ gần sau tôi sẽ chào.\nMở lời em chào nam, chào bắc,\nChào người ngang vai, chào người quân tử,\nChào gái thuyền quyên trong họ ngoài làng (khoan hỡi là hò khoan).\n\n[Verse 2]\nMặc dầu ai có khen chê,\nHai ta giữ dạ chớ hề đổi sai (hò khoan).\nKhen với chê là nghề khán giả,\nDở với hay xin hạ bút tường.\nGiải thưởng treo có bạc có vàng,\nCó anh tư mã, có nàng cung văn.\n\n[Verse 3]\nGặp người quân tử, xin cho nữ hỏi thử đôi câu (ơ hò):\nChàng từ đâu bước tới nơi đây?\nAnh chưa có vợ, hay đã có vợ rồi?\nTuổi anh đây mười tám đôi mươi đương còn xuân,\nDạo chơi giữa chốn ba quân.\nChồng em chưa có, vợ anh chưa bề (khoan hỡi là hò khoan).",
        "is_instrumental": False,
        "featured_in_creation": True,
    },
    "bai_003.mp3": {
        "mode_system": "Điệu Lý - Hơi Bắc tươi sáng (Trong trẻo, đằm thắm)",
        "verse_structure": "Thể thơ Lục bát (10 câu tương ứng 10 nét duyên)",
        "rhyme_guide": "Vần chân chuẩn lục bát (vai - người, hiền - huyền, thanh - vành...), nhịp 2/4 khoan thai, luyến láy 'ơ tang tình tang'",
        "lyrics_with_ornaments": "[Verse 1]\nMột thương (ơ tang tình) tóc xõa ngang vai,\nHai thương đi đứng (nàng ôi) vẻ người có duyên (tình ôi a).\n\n[Verse 2]\nBa thương (ơ tang tình) ăn nói dịu hiền,\nBốn thương mơ mộng mắt huyền thêm xinh (tình ôi a).\n\n[Verse 3]\nNăm thương (ơ tang tình) dáng điệu thanh thanh,\nSáu thương nón Huế những vành nên thơ (tình ôi a).\n\n[Verse 4]\nBảy thương (ơ tang tình) những phút mong chờ,\nTám thương bến đợi Hương Giang hữu tình (tình ôi a).\n\n[Verse 5]\nChín thương (ơ tang tình) em bước nhẹ nhàng,\nMười thương tà áo dịu dàng bay xa (tình ôi a).",
        "is_instrumental": False,
        "featured_in_creation": True,
    },
    "bai_004.mp3": {
        "mode_system": "Điệu Lý - Hơi Dựng sôi động (Hào sảng, khẩn trương)",
        "verse_structure": "Thơ 4 chữ / Lục bát biến thể điệu Lý",
        "rhyme_guide": "Nhịp 4/4 - 2/4 rộn rã mô phỏng vó ngựa, từ đệm 'tính tang lông căng xinh' lặp lại làm điệp khúc vui nhộn",
        "lyrics_with_ornaments": "[Verse 1]\nNgựa ô ơi ngựa ô,\nCám cảnh dưới hồ bắt lên mà thắng (ơ hò).\nTính tang lông căng xinh, tính tang lông căng xinh.\nThiếp đưa chàng chinh lại về dinh,\nThiếp đưa chàng chinh lại về dinh.\n\n[Verse 2]\nNgựa ô ơi ngựa ô,\nEm sắm kiệu vàng em ra cửa Bắc,\nHồ lục làng trong ghép bộ để rước tình thăng.\nTính tang lông căng xinh, tính tang lông căng xinh.\nThiếp đưa chàng chinh lại về dinh,\nThiếp đưa chàng chinh lại về dinh.\n\n[Verse 3]\nNgựa ô ơi ngựa ô,\nCám cảnh dưới hồ bắt lên mà thắng...\nThiếp đưa chàng chinh lại về dinh.",
        "is_instrumental": False,
        "featured_in_creation": True,
    },
    "bai_005.mp3": {
        "mode_system": "Hơi Bắc pha Hơi Nam (Thanh tao, trữ tình mến khách)",
        "verse_structure": "Thơ tự do kết hợp Lục bát",
        "rhyme_guide": "Nhịp 2/4 - 4/4 rộn ràng, điệp khúc 'hồ tang hồ tang tình tang' rộn rã không khí làng nón xứ Huế",
        "lyrics_with_ornaments": "[Verse 1]\nNón nhà bài thơ, nón xinh em tặng cho chàng,\nĐể làm kỷ niệm những ngày qua đò (ơ hò).\n\n[Verse 2]\nQuê em từ thuở bao giờ,\nGái Nam giao dệt lụa tơ, nón nhà bài thơ.\nNón nghiêng nghiêng chẳng nón ai,\nLá ơi lá úp thêm mềm (a í a).\n\n[Chorus]\nHồ tang hồ tang tình tang, gái Huế nhà hồ tang tình tang.\nGái Huế nhà hồ tang tình tang, tình tang hồ tang tình tang.\nVề thăm nhà em rồi mới hay, câu nón từ bài thơ.\nNón quê em trắng đẹp người dưng, nón quê em trắng đẹp người thương.\n\n[Verse 3]\nVườn xanh cây bưởi lá xanh, hoa ơi hoa xin mời cả làng xuống xem.\nHoa ơi là hoa, lòng quê em nặng nghĩa tình, nón với hương trong lòng yêu quê hương.\n\n[Outro]\nNón xinh em tặng cho chàng để làm kỷ niệm,\nƠi chàng ơi, nhớ mãi ngày con đi, nón chàng nay chính là Huế.",
        "is_instrumental": False,
        "featured_in_creation": True,
    },
    "bai_006.mp3": {
        "mode_system": "Điệu Tứ Đại Cảnh - Hơi Dựng pha Oán (Cổ kính, u hoài hoàng cung)",
        "verse_structure": "Thể thơ Phú / Từ khúc cổ điển cung đình (Ưng Bình Thúc Giạ Thị)",
        "rhyme_guide": "Vần trắc chuyển bằng tinh tế, nhịp 3 phách nhàn tản, luyến láy ngũ cung trầm mặc, hoài niệm",
        "lyrics_with_ornaments": "[Verse 1]\nSông Ngân Hà bao nhiêu nước (ơ),\nChim Ô Thước bắc cầu (a í a).\nSông dẫu cạn hãy sâu,\nAi xui lòng chẳng nài công phu trông mấy vạn niên thu.\n\n[Verse 2]\nĐêm Thất Tịch duyên định từ lâu,\nGhi lời hẹn với nhau,\nQua nhịp cầu Chức Nữ với Khiên Ngưu cho tỏ dạ vài câu (tình tang).\n\n[Verse 3]\nCâu ly biệt ai biệt lòng ai,\nAi nhìn mặt không sai.\nMột năm ròng có một bữa mà thôi cho gặp gỡ lại vui.\nĐành đành vui toan cạn chén quỳnh bôi.\n\n[Verse 4]\nNgó lui hiên đài, chuông canh giãi đồng tiền,\nBồng Lai nên vội cả hai.\nPhương đông hé rạng bóng trời mai,\nChia tay khôn rời (a í a).\n\n[Verse 5]\nLưng vơi hàng lụy tuôn rơi đôi nơi,\nPhân phôi một lời,\nNhư lời nguyền đã từng cùng nhau,\nDuyên tái ngộ hãy hiểu về sau.",
        "is_instrumental": False,
        "featured_in_creation": True,
    },
    "bai_007.mp3": {
        "mode_system": "Hơi Bắc pha Nam (Đối đáp tài hoa xứ Huế)",
        "verse_structure": "Thể Lục bát đối đáp giao duyên",
        "rhyme_guide": "Gieo vần đối chữ linh hoạt, nhịp chuyển từ chậm rãi tự tình sang dồn dập tiếng chày gỗ giã gạo",
        "lyrics_with_ornaments": "[Verse 1]\nGiữa chừ viên cỏ điêu la (ơ hò),\nLà có dân quê giã gạo.\nHay đâu có thiếp có chàng,\nUyên ương quân tử đối đàm gặp nhau.\n\n[Verse 2]\nChừ phen đây không có dây tơ Ba Nguyệt,\nXe duyên xe nợ không biết tính làm sao.\nThuyền quyên mới gặp anh hào,\nMột đôi câu nhân nghĩa ta hạp nhau trao gửi.\nNúi Ngự Bình trước tròn sau méo,\nSông An Cựu nắng đục mưa trong.\nĐưa tay trao bức thư phong,\nHỏi thăm bên bạn đà bằng lòng hay chưa?\n\n[Chorus]\nThương em anh phải đi đêm,\nAnh té xuống ruộng đất mềm không đau (khoan hỡi là hò khoan).\nĐất mềm nên mới không đau,\nCớ chi đất cứng ta xa nhau lâu rồi.\nChớ hai ta thì cứ hai ta,\nChớ nghe miệng thế gièm pha mà lìa.\nLìa cành lìa cội lìa cây,\nAi cho mình nỏ mình này lìa nhau.",
        "is_instrumental": False,
        "featured_in_creation": True,
    },
    "inst_001.mp3": {
        "mode_system": "Hơi Bắc - Nhã nhạc cung đình (Đàng hoàng, trang trọng, tươi sáng)",
        "verse_structure": "Bản đàn lòng bản không lời",
        "rhyme_guide": "Nhịp 2/4 đĩnh đạc, ngón nhấn ngón rung ngón vê đặc trưng Đàn Nguyệt Huế",
        "lyrics_with_ornaments": "[Instrumental - Độc tấu Đàn Nguyệt Hơi Bắc]",
        "is_instrumental": True,
        "featured_in_creation": True,
    },
    "inst_002.mp3": {
        "mode_system": "Hơi Bắc - Nhã nhạc cung đình (Hùng dũng, khí thế)",
        "verse_structure": "Bản đàn lòng bản không lời",
        "rhyme_guide": "Nhịp 2/4 rộn rã, phách mạnh dứt khoát mô phỏng rồng bay hổ lượn",
        "lyrics_with_ornaments": "[Instrumental - Độc tấu Đàn Nguyệt Hơi Bắc]",
        "is_instrumental": True,
        "featured_in_creation": True,
    },
    "inst_003.mp3": {
        "mode_system": "Hơi Bắc - Nhã nhạc cung đình (Êm đềm, thanh thoát như dòng nước trôi)",
        "verse_structure": "Bản đàn lòng bản không lời",
        "rhyme_guide": "Nhịp vừa phải, giai điệu dạt dào êm đềm mô phỏng dòng sông Hương lững lờ",
        "lyrics_with_ornaments": "[Instrumental - Độc tấu Đàn Nguyệt Hơi Bắc]",
        "is_instrumental": True,
        "featured_in_creation": True,
    },
    "inst_004.mp3": {
        "mode_system": "Hơi Bắc - Nhã nhạc cung đình (Tươi vui, phơi phới gió xuân)",
        "verse_structure": "Bản đàn lòng bản không lời",
        "rhyme_guide": "Nhịp 2/4 nhẹ nhàng, tiếng đàn thanh thoát đón mừng mùa xuân sang",
        "lyrics_with_ornaments": "[Instrumental - Độc tấu Đàn Nguyệt Hơi Bắc]",
        "is_instrumental": True,
        "featured_in_creation": True,
    },
    "inst_005.mp3": {
        "mode_system": "Quốc thiều triều Nguyễn - Hơi Bắc (Trang nghiêm, thành kính hoàng triều)",
        "verse_structure": "Bản đàn lòng bản lễ nhạc cung đình",
        "rhyme_guide": "Nhịp chậm trang nghiêm, phách điểm khoan thai thể hiện uy quyền hoàng gia triều Nguyễn",
        "lyrics_with_ornaments": "[Instrumental - Quốc thiều Đăng Đàn Cung]",
        "is_instrumental": True,
        "featured_in_creation": True,
    },
    "inst_006.mp3": {
        "mode_system": "Đại nhạc lễ cung đình (Uy vũ, hào hùng)",
        "verse_structure": "Đại nhạc lễ nghi thức hoàng gia",
        "rhyme_guide": "Song tấu kèn bầu kèn bóp và trống chiến giục giã, không khí lễ nghi triều đình",
        "lyrics_with_ornaments": "[Instrumental - Đại nhạc Trống Kèn]",
        "is_instrumental": True,
        "featured_in_creation": True,
    },
}


def make_placeholder_wav() -> bytes:
    bio = io.BytesIO()
    w = wave.open(bio, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(16000)
    n = 16000
    frames = [int(0.25 * 32767 * math.sin(2 * 3.141592653589793 * 440.0 * i / 16000)) for i in range(n)]
    w.writeframes(struct.pack("<%dh" % n, *frames))
    w.close()
    return bio.getvalue()


def seed():
    init_db()
    db = SessionLocal()
    seeded_count = 0
    updated_count = 0

    sources = [
        (DATASETS_DIR / "ca_hue" / "metadata.json", DATASETS_DIR / "ca_hue"),
        (DATASETS_DIR / "instruments" / "metadata.json", DATASETS_DIR / "instruments"),
    ]

    has_source_files = any(meta.exists() for meta, _ in sources)

    try:
        if has_source_files:
            for meta_file, base_dir in sources:
                if not meta_file.exists():
                    continue
                with open(meta_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                entries = data.get("entries", [])
                for entry in entries:
                    audio_name = entry.get("audio", "")
                    audio_path = base_dir / audio_name
                    if not audio_path.exists():
                        continue

                    audio_bytes = audio_path.read_bytes()
                    sha = manager.sha256_bytes(audio_bytes)
                    existing = crud.get_by_sha(db, sha)

                    ext_meta = MUSICOLOGY_EXTENSIONS.get(audio_name, {})
                    title = entry.get("title", audio_path.stem)
                    item_type = entry.get("type", "Ca Huế")
                    artist = entry.get("artist", "Nghệ nhân dân gian Huế")

                    merged_meta = {
                        "genre": entry.get("genre", ""),
                        "composer": entry.get("composer", ""),
                        "performers": entry.get("performers", ""),
                        "artisans": entry.get("artisans", ""),
                        "collector": entry.get("collector", ""),
                        "recorded_time": entry.get("recorded_time", ""),
                        "location": entry.get("location", "Huế"),
                        "source": entry.get("source", "Dữ liệu di sản"),
                        "license": entry.get("license", ""),
                        "lyrics": entry.get("lyrics", ""),
                        "instruments": entry.get("instruments", ""),
                        "tonal": entry.get("tonal", ""),
                        "description": entry.get("caption", ""),
                        "notes": entry.get("notes", ""),
                        "bpm": float(entry.get("bpm", 0)) if entry.get("bpm") else None,
                        **ext_meta,
                    }

                    if not existing:
                        item, created = heritage_service.ingest_upload(
                            db, audio_bytes, audio_name, title, item_type, artist=artist, **merged_meta
                        )
                        if created:
                            seeded_count += 1
                    else:
                        crud.update_item_metadata(db, existing.id, **merged_meta)
                        updated_count += 1
        else:
            sample_audio = make_placeholder_wav()
            for filename, default_info in DEFAULT_CATALOG.items():
                ext_meta = MUSICOLOGY_EXTENSIONS.get(filename, {})
                title = default_info.get("title", filename)
                item_type = default_info.get("type", "Ca Huế")
                artist = default_info.get("artist", "Nghệ nhân dân gian Huế")

                existing_items = crud.list_items(db, q=title, limit=10)
                matched = [i for i in existing_items if i.title == title]
                existing = matched[0] if matched else None

                merged_meta = {
                    "genre": default_info.get("genre", ""),
                    "composer": default_info.get("composer", ""),
                    "performers": default_info.get("performers", ""),
                    "artisans": default_info.get("artisans", ""),
                    "collector": default_info.get("collector", ""),
                    "recorded_time": default_info.get("recorded_time", ""),
                    "location": "Huế",
                    "source": "Di sản văn hóa Huế",
                    "license": "Phi thương mại / Nghiên cứu",
                    "lyrics": default_info.get("lyrics", ""),
                    "instruments": default_info.get("instruments", ""),
                    "tonal": ext_meta.get("mode_system", ""),
                    "description": default_info.get("genre", ""),
                    "notes": "",
                    "bpm": default_info.get("bpm"),
                    **ext_meta,
                }

                if not existing:
                    item, created = heritage_service.ingest_upload(
                        db, sample_audio, filename.replace(".mp3", ".wav"), title, item_type, artist=artist, **merged_meta
                    )
                    if created:
                        seeded_count += 1
                else:
                    crud.update_item_metadata(db, existing.id, **merged_meta)
                    updated_count += 1

        print(f"Seeding completed: {seeded_count} newly created, {updated_count} updated.")
    finally:
        db.close()


if __name__ == "__main__":
    seed()
